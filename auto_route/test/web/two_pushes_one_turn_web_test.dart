// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, two pushes in one turn write two browser entries, one for each
// page. The router writes the url once a frame, after it, so the first page
// had no entry: the browser's back button from the second skipped it and
// went to the page under both, and forward reopened the second from its url
// alone, without its arguments.
//
// Native behavior this holds to: the HTML History API; two history.pushState
// calls add two entries. Flutter's own Navigator, with
// reportsRouteUpdateToEngine, writes each push to the engine as it flushes
// (Navigator._flushHistoryUpdates), so two pushes add two entries there too.
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

// The browser's entry and url, the names on the router's stack, and the top
// page's arguments, as one value, so a failure prints them all.
(int, String, String, Object?) _shown(RootStackRouter router) => (
  browserSerialCount,
  browserPath,
  router.stack.map((m) => m.name).join(' '),
  router.current.args,
);

// Pumps Home and returns the router and Home's browser entry.
Future<(RootStackRouter, int)> _pumpHome(WidgetTester tester) async {
  final router = _router();
  await pumpRouterConfigApp(tester, router.config());
  await settleBrowser(tester);
  return (router, browserSerialCount);
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: push A, and in the same turn push B with arguments the url can't
  // carry; press the browser's back button, then its forward button.
  testWidgets('On web, two pushes in one turn get a browser entry each', (
    tester,
  ) async {
    final (router, home) = await _pumpHome(tester);

    unawaited(router.push(const NamedRoute('ARoute')));
    unawaited(router.push(const NamedRoute('BRoute', args: 'draft 7')));
    await settleBrowser(tester);
    final afterPushes = _shown(router);
    // The Chrome runner doesn't print a failed expectation.
    printOnFailure('after the pushes: $afterPushes');
    // Checked before the browser moves, so a missing entry fails here.
    expect(afterPushes, (home + 2, '/b', 'HomeRoute ARoute BRoute', 'draft 7'));

    // After back, and after forward.
    final readings = <(int, String, String, Object?)>[];
    for (final move in [pressBrowserBack, pressBrowserForward]) {
      await move(tester);
      readings.add(_shown(router));
    }
    printOnFailure('after back and forward: $readings');
    expect(readings, [
      (home + 1, '/a', 'HomeRoute ARoute', null),
      (home + 2, '/b', 'HomeRoute ARoute BRoute', 'draft 7'),
    ]);
  });

  // Steps: push A and B in one turn, and after an await that completes at
  // once, replace B with C; then press the browser's back button.
  testWidgets('On web, a replace after two pushes in one frame takes the '
      "second page's entry", (tester) async {
    final (router, home) = await _pumpHome(tester);

    unawaited(router.push(const NamedRoute('ARoute')));
    unawaited(router.push(const NamedRoute('BRoute')));
    await Future<void>.delayed(.zero);
    unawaited(router.replace(const NamedRoute('CRoute')));
    await settleBrowser(tester);
    final afterReplace = _shown(router);
    printOnFailure('after the replace: $afterReplace');
    // Checked before the browser moves, so a missing entry fails here.
    expect(afterReplace, (home + 2, '/c', 'HomeRoute ARoute CRoute', null));

    await pressBrowserBack(tester);
    printOnFailure('after back: ${_shown(router)}');
    expect(_shown(router), (home + 1, '/a', 'HomeRoute ARoute', null));
  });
}
