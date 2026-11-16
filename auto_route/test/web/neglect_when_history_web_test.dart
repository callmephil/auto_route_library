// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, an app that keeps a url out of the address bar with
// neglectWhen moves through the browser's history without reloading itself:
// a pop from the page kept out steps the browser back at most, never by 0,
// which reloads the page and starts the app again. A page kept out has no
// browser entry, so the history must not count one for it. A pin for the
// web history's next rework.
//
// Native behavior this holds to: the HTML History API; history.go(0) reloads
// the document, and a page kept out of the address bar has no entry to step
// back over.
//
// And whatever the calls around the page kept out, a frame apart as in one
// turn: the address bar shows the url of the page nearest the top that is
// not kept out, and the browser stands as many entries over Home's as there
// are such pages over Home. Was, in one turn and after a replace or
// popUntilRoot over the page kept out: an entry too many, an entry of a
// closed page, or the url of a page under the one shown.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

// Records each history.go call, and leaves out one by 0, which would reload
// the test page and end the run.
void _recordHistoryGo() {
  globalContext.callMethod(
    'eval'.toJS,
    '''
(function () {
  if (window.__goCalls) { window.__goCalls.length = 0; return; }
  window.__goCalls = [];
  var h = window.history, go = h.go.bind(h);
  h.go = function (n) {
    window.__goCalls.push(n === undefined ? 0 : n);
    if (!n) return;
    return go(n);
  };
})()
'''
        .toJS,
  );
}

List<String> _historyGoCalls() {
  final calls = globalContext.callMethod<JSString?>(
    'eval'.toJS,
    'window.__goCalls.join(",")'.toJS,
  );
  final text = calls?.toDart ?? '';
  return text.isEmpty ? const [] : text.split(',');
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: with /a kept out of the address bar, push A and pop it, a frame
  // apart.
  testWidgets('On web, with /a kept out of the address bar, a push of A and a '
      'pop never reload the page', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(neglectWhen: (location) => location == '/a'),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    _recordHistoryGo();
    unawaited(router.push(const NamedRoute('ARoute')));
    await settleBrowser(tester);
    router.pop();
    await settleBrowser(tester);
    final shown = (
      browserSerialCount - home,
      browserPath,
      router.stack.map((page) => page.name).join(' '),
    );
    // The Chrome runner doesn't print a failed expectation.
    printOnFailure('after the pop: $shown; history.go: ${_historyGoCalls()}');
    expect(
      (shown, _historyGoCalls().any((steps) => int.parse(steps) >= 0)),
      ((0, '/', 'HomeRoute'), false),
    );
  });

  // Steps: with /a kept out of the address bar, make the calls on Home.
  // Each word is a call: a letter pushes that page, 'pop' pops, 'rB'
  // replaces the page on top with B, 'root' is popUntilRoot.
  for (final calls in [
    'A rB',
    'B A C',
    'B A C pop',
    'A B C root',
    'B A root',
    'A pop A pop',
    'B A rC',
    'A rB pop',
    'A rB rC',
    'A rB B',
    'B A rC pop',
    'A B rC',
    'A A rB',
    'B A A rC',
    'B A pop rC',
    'A B root',
    'B A C root',
    'B A rC root',
    'A B pop rC',
  ]) {
    for (final isOneTurn in [false, true]) {
      testWidgets('On web, with /a kept out of the address bar, after '
          '"$calls" ${isOneTurn ? 'in one turn' : 'a frame apart'} the '
          'browser holds an entry for each page not kept out', (tester) async {
        final router = _router();
        await pumpRouterConfigApp(
          tester,
          router.config(neglectWhen: (location) => location == '/a'),
        );
        await settleBrowser(tester);
        final home = browserSerialCount;
        _recordHistoryGo();
        for (final call in calls.split(' ')) {
          switch (call) {
            case 'pop':
              router.pop();
            case 'root':
              router.popUntilRoot();
            case final replace when replace.startsWith('r'):
              unawaited(
                router.replace(NamedRoute('${replace.substring(1)}Route')),
              );
            default:
              unawaited(router.push(NamedRoute('${call}Route')));
          }
          if (!isOneTurn) await settleBrowser(tester);
        }
        await settleBrowser(tester);

        final shown = [
          for (final page in router.stack)
            if (page.name != 'ARoute') page.name,
        ];
        final url = switch (shown.lastOrNull) {
          'BRoute' => '/b',
          'CRoute' => '/c',
          _ => '/',
        };
        printOnFailure(
          'after the calls: ${browserSerialCount - home} $browserPath, '
          'pages ${router.stack.map((page) => page.name).join(' ')}; '
          'history.go: ${_historyGoCalls()}',
        );
        expect(
          (
            browserSerialCount - home,
            browserPath,
            _historyGoCalls().any((steps) => int.parse(steps) >= 0),
          ),
          (shown.length - 1, url, false),
        );
      });
    }
  }

  // Steps: open the app at /a, which it keeps out of the address bar, then
  // make the calls, a frame apart and in one turn.
  // The browser made the entry for /a when it opened the app, so A has it:
  // a push over A gets a new entry, and back from it shows A. Native
  // behavior this holds to: the HTML History API, where the back button
  // goes to the entry the browser opened.
  for (final (calls, url, entry) in [
    ('push B', '/b', 1),
    ('push B, pop', '/a', 0),
    ('replace with B', '/b', 0),
    ('replaceAll with C', '/c', 0),
  ]) {
    for (final isOneTurn in [false, true]) {
      testWidgets('On web, opened at /a, kept out of the address bar, after '
          '"$calls" ${isOneTurn ? 'in one turn' : 'a frame apart'} the '
          'browser stands on the entry of the page shown', (tester) async {
        final start = browserSerialCount < 0 ? 0 : browserSerialCount;
        final router = _router();
        addTearDown(router.dispose);
        openBrowserAt(tester, '/a');
        await pumpAsRunApp(
          tester,
          MaterialApp.router(
            routerConfig: router.config(
              neglectWhen: (location) => location == '/a',
            ),
          ),
        );
        await settleBrowser(tester);
        _recordHistoryGo();
        final steps = <void Function()>[
          if (calls.startsWith('push B'))
            () => unawaited(router.push(const NamedRoute('BRoute'))),
          if (calls.endsWith('pop')) router.pop,
          if (calls == 'replace with B')
            () => unawaited(router.replace(const NamedRoute('BRoute'))),
          if (calls == 'replaceAll with C')
            () => unawaited(router.replaceAll(const [NamedRoute('CRoute')])),
        ];
        for (final step in steps) {
          step();
          if (!isOneTurn) await settleBrowser(tester);
        }
        await settleBrowser(tester);

        printOnFailure(
          'after the calls: ${browserSerialCount - start} $browserPath, '
          'pages ${router.stack.map((page) => page.name).join(' ')}; '
          'history.go: ${_historyGoCalls()}',
        );
        expect(
          (
            browserSerialCount - start,
            browserPath,
            _historyGoCalls().any((delta) => int.parse(delta) >= 0),
          ),
          (entry, url, false),
        );
      });
    }
  }
}
