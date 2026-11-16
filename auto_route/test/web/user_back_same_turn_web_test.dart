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

// On the web, a press of the browser's back button that comes while the
// history's own step back is still on its way ends where the browser ends,
// both steps taken, and the app shows the page of that entry: the address
// bar names the page on screen, and no later back press reopens a page the
// app closed.
//
// Before, on Home, A, B and C, an app that called pop, pop and push(D) in
// one handler, with the back button pressed in the same turn, ended with D
// on screen and the browser on Home's entry, the address bar at /. The app
// had followed the user's landing on B's entry halfway and taken it as D's,
// and the history's own step then landed unseen. A push of E went over B's
// entry, so the first back press from E showed B again over E.
//
// The steps: the app's calls and `window.history.back()`, the call the back
// button makes, in the same turn or 3 microtasks later; then a push of E and
// the back button down to Home. The cases that worked before stay as they
// were: a pop with the back button, and a push with the back button.
//
// Native behavior this holds to: the HTML History API as Chrome runs it,
// where a history.go(-1) and a history.back() asked close together both
// run, one after the other: a raw run from #/r4 lands on #/r3, then #/r2.
// And Flutter's Navigator, where back never reopens a closed route. Where
// the browser takes both steps back, as here, the app follows it to the
// entry it ends on.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
      ('ERoute', '/e'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

String _stack(RootStackRouter router) =>
    router.stack.map((page) => page.name?.replaceAll('Route', '')).join(' ');

void _pop(RootStackRouter router) => router.pop();

void _pushC(RootStackRouter router) =>
    unawaited(router.push(const NamedRoute('CRoute')));

void _popPopPushD(RootStackRouter router) {
  for (var i = 0; i < 2; i++) {
    router.pop();
  }
  unawaited(router.push(const NamedRoute('DRoute')));
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Each case: the pages pushed over Home, the app's calls, the microtasks
  // before the back button, the reading once settled, and the readings
  // after a push of E and each back press from there.
  final cases = {
    'on Home A B C: pop, back in the same turn': (
      ['ARoute', 'BRoute', 'CRoute'],
      _pop,
      0,
      '(1, /a, Home A)',
      ['(2, /e, Home A E)', '(1, /a, Home A)', '(0, /, Home)'],
    ),
    'on Home A B C: pop, back 3 microtasks later': (
      ['ARoute', 'BRoute', 'CRoute'],
      _pop,
      3,
      '(1, /a, Home A)',
      ['(2, /e, Home A E)', '(1, /a, Home A)', '(0, /, Home)'],
    ),
    'on Home A B C: pop, pop, push D, back in the same turn': (
      ['ARoute', 'BRoute', 'CRoute'],
      _popPopPushD,
      0,
      '(0, /, Home)',
      ['(1, /e, Home E)', '(0, /, Home)'],
    ),
    'on Home A B C: pop, pop, push D, back 3 microtasks later': (
      ['ARoute', 'BRoute', 'CRoute'],
      _popPopPushD,
      3,
      '(0, /, Home)',
      ['(1, /e, Home E)', '(0, /, Home)'],
    ),
    'on Home A B: push C, back in the same turn': (
      ['ARoute', 'BRoute'],
      _pushC,
      0,
      '(1, /a, Home A)',
      ['(2, /e, Home A E)', '(1, /a, Home A)', '(0, /, Home)'],
    ),
  };

  for (final MapEntry(
        key: name,
        value: (opens, calls, microtasks, settled, afterE),
      )
      in cases.entries) {
    testWidgets(name, (tester) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final home = browserSerialCount;
      for (final page in opens) {
        unawaited(router.push(NamedRoute(page)));
        await settleBrowser(tester);
      }
      String reading() =>
          '(${browserSerialCount - home}, $browserPath, ${_stack(router)})';
      calls(router);
      for (var i = 0; i < microtasks; i++) {
        await Future<void>.value();
      }
      window.history.back();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleBrowser(tester);
      // Longer than the history waits for a step to land.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await settleBrowser(tester);
      final atSettle = reading();
      final urlState = router.urlState.url;
      unawaited(router.push(const NamedRoute('ERoute')));
      await settleBrowser(tester);
      final walk = [reading()];
      for (var i = 0; i < 5 && browserSerialCount > home; i++) {
        await pressBrowserBack(tester);
        walk.add(reading());
      }
      debugPrint(
        '$name: settled $atSettle, urlState $urlState; push E and each '
        'back $walk',
      );
      expect(atSettle, settled);
      expect(urlState, atSettle.split(', ').elementAtOrNull(1));
      expect(walk, afterE);
    });
  }
}
