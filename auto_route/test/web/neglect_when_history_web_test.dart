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
// a pop from the page kept out, and a pop back onto it, step the browser back
// at most, never by 0, which reloads the page and starts the app again. The
// web history counted an entry for the page kept out, which the browser
// never got, so its next step back was history.go(0) (e8ca1958).
//
// And a replace of the page kept out gives the new page an entry of its own:
// on Home, push A, then replace it with B, and the browser shows /b with
// Home's entry still under it, so its back button returns to Home. The web
// history took the replace for one of an entry, but the page kept out has
// none, so B's url wrote over Home's entry and back left the app.
//
// Native behavior this holds to: the HTML History API; history.go(0) reloads
// the document, a page kept out of the address bar has no entry to step
// back over, and replaceState changes only the current entry, which the
// page kept out never had.
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

typedef _Reading = (int, String, String);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // With /a kept out of the address bar, each case runs its steps a frame
  // apart, then presses the browser's back button until it is at Home's entry
  // again. A letter pushes that page, 'pop' pops, 'rB' replaces the top with
  // B and 'root' pops until the root. Each reading is the browser's entry,
  // counted from Home's, its url, and the names on the router's stack.
  for (final (steps, expected) in <(String, List<_Reading>)>[
    ('A pop', [(0, '/', 'HomeRoute')]),
    ('A B pop', [(0, '/', 'HomeRoute ARoute')]),
    ('A rB', [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')]),
    (
      'B A rC',
      [
        (2, '/c', 'HomeRoute BRoute CRoute'),
        (1, '/b', 'HomeRoute BRoute'),
        (0, '/', 'HomeRoute'),
      ],
    ),
    ('B A root', [(0, '/', 'HomeRoute')]),
  ]) {
    testWidgets('On web, with /a kept out of the address bar, $steps keep the '
        'browser history and never reload the page', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(neglectWhen: (location) => location == '/a'),
      );
      await settleBrowser(tester);
      final home = browserSerialCount;
      _Reading shown() => (
        browserSerialCount - home,
        browserPath,
        router.stack.map((page) => page.name).join(' '),
      );
      _recordHistoryGo();
      for (final step in steps.split(' ')) {
        switch (step) {
          case 'pop':
            router.pop();
          case 'root':
            router.popUntilRoot();
          case final replace when replace.startsWith('r'):
            unawaited(
              router.replace(NamedRoute('${replace.substring(1)}Route')),
            );
          default:
            unawaited(router.push(NamedRoute('${step}Route')));
        }
        await settleBrowser(tester);
      }
      final readings = [shown()];
      while (readings.length < expected.length && browserSerialCount > home) {
        await pressBrowserBack(tester);
        readings.add(shown());
      }
      // The Chrome runner doesn't print a failed expectation.
      printOnFailure('readings: $readings; history.go: ${_historyGoCalls()}');
      expect(readings, expected);
      expect(_historyGoCalls().where((step) => int.parse(step) >= 0), isEmpty);
    });
  }
}
