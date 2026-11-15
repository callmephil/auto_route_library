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
// And in one turn: on Home, push B, push A, then pop twice or popUntilRoot,
// and the browser ends on Home's entry, as the same calls a frame apart. Was:
// a second '/' entry over Home's, or '/', '/b', '/' with back showing B, a
// closed page: the history counted an entry for A, which the browser never
// got.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
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

  // Steps, in one turn: with /a kept out of the address bar, on Home push B,
  // push A, then pop twice, or popUntilRoot.
  for (final (name, closeBoth) in <(String, void Function(RootStackRouter))>[
    (
      'two pops',
      (router) {
        for (var i = 0; i < 2; i++) {
          router.pop();
        }
      },
    ),
    ('popUntilRoot', (router) => router.popUntilRoot()),
  ]) {
    testWidgets('On web, with /a kept out of the address bar, a push of B and '
        'of A and $name in one turn end on the entry of Home', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(neglectWhen: (location) => location == '/a'),
      );
      await settleBrowser(tester);
      final home = browserSerialCount;
      _recordHistoryGo();
      unawaited(router.push(const NamedRoute('BRoute')));
      unawaited(router.push(const NamedRoute('ARoute')));
      closeBoth(router);
      await settleBrowser(tester);
      final shown = (
        browserSerialCount - home,
        browserPath,
        router.stack.map((page) => page.name).join(' '),
      );
      printOnFailure(
        'after the calls: $shown; history.go: '
        '${_historyGoCalls()}',
      );
      expect(
        (shown, _historyGoCalls().any((steps) => int.parse(steps) >= 0)),
        ((0, '/', 'HomeRoute'), false),
      );
    });
  }
}
