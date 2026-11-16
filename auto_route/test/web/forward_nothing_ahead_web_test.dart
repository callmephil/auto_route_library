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

// On the web, navigationHistory.forward() with no entry ahead does nothing,
// and what the app does next reaches the browser at once.
//
// Before, the history asked the browser for the step and waited for a
// landing that never came, up to its one-second limit, and held every
// write behind it: after forward() and a push of B, B was on screen while
// the address bar kept /a for a second, and a back press in that second
// closed B and A together, since B had no entry yet.
//
// The steps: on Home and A, forward(), then a push of B in the same turn or
// a frame later; and the same with the browser's back button pressed 300
// ms after the push.
//
// Native behavior this holds to: the HTML History API as Chrome runs it,
// where history.forward() with no entry ahead does nothing, and a
// history.pushState right after it is in the address bar at once, with no
// popstate (a raw run of forward() then pushState in this browser); and
// Flutter's Navigator, where back after a push closes that page alone.
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

String _stack(RootStackRouter router) =>
    router.stack.map((page) => page.name?.replaceAll('Route', '')).join(' ');

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Opens the app on Home and pushes A; returns the router and the number
  // of Home's browser entry.
  Future<(RootStackRouter, int)> openOnA(WidgetTester tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute('ARoute')));
    await settleBrowser(tester);
    return (router, home);
  }

  for (final isFrameLater in [false, true]) {
    final when = isFrameLater ? 'a frame later' : 'in the same turn';
    testWidgets('forward(), then a push of B $when: /b shows with B', (
      tester,
    ) async {
      final (router, home) = await openOnA(tester);
      String reading() =>
          '(${browserSerialCount - home}, $browserPath, ${_stack(router)})';
      final stopwatch = Stopwatch()..start();
      router.navigationHistory.forward();
      if (isFrameLater) await tester.pump(const Duration(milliseconds: 16));
      unawaited(router.push(const NamedRoute('BRoute')));
      int? shownAt;
      int? inAddressBarAt;
      while (stopwatch.elapsedMilliseconds < 1500 &&
          (shownAt == null || inAddressBarAt == null)) {
        await tester.pump(const Duration(milliseconds: 20));
        final ms = stopwatch.elapsedMilliseconds;
        if (find.text('BRoute').evaluate().isNotEmpty) shownAt ??= ms;
        if (browserPath == '/b') inAddressBarAt ??= ms;
      }
      await settleBrowser(tester);
      final settled = reading();
      // -1: never within the time.
      final shown = shownAt ?? -1;
      final inAddressBar = inAddressBarAt ?? -1;
      debugPrint(
        'forward then push B $when: B shown at ${shown}ms, /b in the '
        'address bar at ${inAddressBar}ms; settled $settled',
      );
      expect([shown, inAddressBar], everyElement(isNonNegative));
      expect((inAddressBar - shown).abs(), lessThan(200));
      expect(settled, '(2, /b, Home A B)');
    });
  }

  testWidgets('forward(), a push of B, back pressed 300 ms later closes B', (
    tester,
  ) async {
    final (router, home) = await openOnA(tester);
    String reading() =>
        '(${browserSerialCount - home}, $browserPath, ${_stack(router)})';
    router.navigationHistory.forward();
    unawaited(router.push(const NamedRoute('BRoute')));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Before the back press, then settled after it.
    final readings = [reading()];
    window.history.back();
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsedMilliseconds < 1500) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleBrowser(tester);
    readings.add(reading());
    debugPrint('forward, push B, back: before and settled $readings');
    expect(readings.lastOrNull, '(1, /a, Home A)');
  });

  // An entry ahead: forward() still steps the browser to it, and the app
  // follows, as history.forward() lands there.
  testWidgets('forward() after a back step reopens A', (tester) async {
    final (router, home) = await openOnA(tester);
    String reading() =>
        '(${browserSerialCount - home}, $browserPath, ${_stack(router)})';
    await browserMove(tester, router.navigationHistory.back);
    final readings = [reading()];
    await browserMove(tester, router.navigationHistory.forward);
    readings.add(reading());
    debugPrint('back, then forward: $readings');
    expect(readings, ['(0, /, Home)', '(1, /a, Home A)']);
  });
}
