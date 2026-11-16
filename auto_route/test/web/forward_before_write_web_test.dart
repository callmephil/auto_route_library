// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, when a step forward lands on the browser entry the page on
// top is about to get, before its url is written there, the page stays and
// its url is written over that entry: the address bar names the page on
// screen, and no later back press shows a page the app closed.
//
// Before, the app took the old entry for the page's own: on Home, A, B, C
// with D and E ahead, pop, pop and push(F) with the browser's forward
// button pressed in the same turn ended with F on screen and /b in the
// address bar, and after a push of X the first back press showed B over X.
// The same after forward() with an entry ahead and a push in one turn: B on
// screen, /a in the address bar.
//
// The steps: the app's calls and `window.history.forward()`, the call the
// forward button makes, in the same turn; then a push of X and the back
// button down to Home. And forward() over an entry ahead, then a push.
//
// Native behavior this holds to: the HTML History API as Chrome runs it,
// where a forward and a history.go(-2) asked together both run, the second
// counted from where the first landed (a raw run from #/n7-4 with two
// entries ahead lands on #/n7-5, then #/n7-3), and where history.forward()
// then history.pushState in one task leave the pushed url in the address
// bar; and Flutter's Navigator, where back never reopens a closed route.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
      ('ERoute', '/e'),
      ('FRoute', '/f'),
      ('XRoute', '/x'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

String _stack(RootStackRouter router) =>
    router.stack.map((page) => page.name?.replaceAll('Route', '')).join(' ');

void _popPopPushF(RootStackRouter router) {
  for (var i = 0; i < 2; i++) {
    router.pop();
  }
  unawaited(router.push(const NamedRoute('FRoute')));
}

void _popUntilRootPushF(RootStackRouter router) {
  router.popUntilRoot();
  unawaited(router.push(const NamedRoute('FRoute')));
}

// The browser entry counted from Home's, the address bar, the stack, and
// the router's own url where it differs from the address bar.
String _reading(RootStackRouter router, int home) {
  final url = router.urlState.url.isEmpty ? '/' : router.urlState.url;
  final odd = url == browserPath ? '' : ' urlState $url';
  return '(${browserSerialCount - home}, $browserPath, ${_stack(router)})$odd';
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  final cases = {
    'pop, pop, push F': (
      _popPopPushF,
      ['(2, /f, Home A F)', '(3, /x, Home A F X)', '(2, /f, Home A F)'],
    ),
    'popUntilRoot, push F': (
      _popUntilRootPushF,
      ['(1, /f, Home F)', '(2, /x, Home F X)', '(1, /f, Home F)'],
    ),
  };

  for (final MapEntry(key: name, value: (calls, expected)) in cases.entries) {
    testWidgets('C on top, D and E ahead: $name, forward in the same turn', (
      tester,
    ) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final home = browserSerialCount;
      for (final page in ['ARoute', 'BRoute', 'CRoute', 'DRoute', 'ERoute']) {
        unawaited(router.push(NamedRoute(page)));
        await settleBrowser(tester);
      }
      for (var i = 0; i < 2; i++) {
        await pressBrowserBack(tester);
      }
      calls(router);
      window.history.forward();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleBrowser(tester);
      // Longer than the history waits for a step to land.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await settleBrowser(tester);
      final readings = [_reading(router, home)];
      unawaited(router.push(const NamedRoute('XRoute')));
      await settleBrowser(tester);
      readings.add(_reading(router, home));
      await pressBrowserBack(tester);
      readings.add(_reading(router, home));
      expect(readings, expected);
    });
  }

  testWidgets('forward() over an entry ahead, then a push of B', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute('ARoute')));
    await settleBrowser(tester);
    await pressBrowserBack(tester);
    router.navigationHistory.forward();
    unawaited(router.push(const NamedRoute('BRoute')));
    await settleBrowser(tester);
    final readings = [_reading(router, home)];
    await pressBrowserBack(tester);
    readings.add(_reading(router, home));
    expect(readings, ['(1, /b, Home B)', '(0, /, Home)']);
  });
}
