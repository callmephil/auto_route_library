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

// On the web, an app that gives MaterialApp.router the router's delegate()
// and defaultRouteParser() only, so the Router uses Flutter's own route
// information provider, gets the browser history right for navigations in
// one turn too: two pushes, a push and a replace, a replace and a push,
// replaceAll and a push, and a replace and a pop. With e8ca1958 only an app
// on router.config() did; the others ended as on dev, with an entry lost or
// one too many.
//
// Native behavior this holds to: the HTML History API, whose pushState,
// replaceState and back() change the history at once, one call after
// another.
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

typedef _Call = void Function(RootStackRouter router);
typedef _Reading = (int, String, String);

_Call _push(String name) =>
    (router) => unawaited(router.push(NamedRoute(name)));
_Call _replace(String name) =>
    (router) => unawaited(router.replace(NamedRoute(name)));
void _pop(RootStackRouter router) => router.pop();
void _replaceAllWithC(RootStackRouter router) =>
    unawaited(router.replaceAll(const [NamedRoute('CRoute')]));

// The browser's entry, counted from [home]'s, its url, and the names on the
// router's stack.
_Reading _shown(RootStackRouter router, int home) => (
  browserSerialCount - home,
  browserPath,
  router.stack.map((page) => page.name).join(' '),
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Each case opens A over Home first when it says so, runs its calls in one
  // turn, then presses the browser's back button once for each further
  // reading.
  final cases = [
    (
      'two pushes',
      false,
      [_push('ARoute'), _push('BRoute')],
      [
        (2, '/b', 'HomeRoute ARoute BRoute'),
        (1, '/a', 'HomeRoute ARoute'),
        (0, '/', 'HomeRoute'),
      ],
    ),
    (
      'a push and a replace',
      false,
      [_push('ARoute'), _replace('BRoute')],
      [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')],
    ),
    (
      'a replace and a push',
      true,
      [_replace('BRoute'), _push('CRoute')],
      [
        (2, '/c', 'HomeRoute BRoute CRoute'),
        (1, '/b', 'HomeRoute BRoute'),
        (0, '/', 'HomeRoute'),
      ],
    ),
    (
      'replaceAll and a push',
      true,
      [_replaceAllWithC, _push('BRoute')],
      [(2, '/b', 'CRoute BRoute'), (1, '/c', 'CRoute')],
    ),
    (
      'a replace and a pop',
      true,
      [_replace('BRoute'), _pop],
      [(0, '/', 'HomeRoute')],
    ),
  ];
  for (final (name, startsOnA, calls, expected) in cases) {
    testWidgets(
      "On web, with Flutter's route information provider, $name in one turn "
      'keep the browser history',
      (tester) async {
        final router = _router();
        // The delegate and the parser, no provider of the router's own.
        await pumpRouterApp(tester, router);
        await settleBrowser(tester);
        final home = browserSerialCount;
        if (startsOnA) {
          unawaited(router.push(const NamedRoute('ARoute')));
          await settleBrowser(tester);
        }
        for (final call in calls) {
          call(router);
        }
        await settleBrowser(tester);
        final [expectedAfterCalls, ...expectedAfterBacks] = expected;
        // A step back the browser makes at the turn's end lands after a
        // while: up to two seconds, then the check below fails.
        for (var i = 0; i < 20; i++) {
          if (_shown(router, home) == expectedAfterCalls) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await settleBrowser(tester);
        }
        final afterCalls = _shown(router, home);
        // The Chrome runner doesn't print a failed expectation.
        printOnFailure('after the calls: $afterCalls');
        // Checked before the browser moves, so a missing entry fails here.
        expect(afterCalls, expectedAfterCalls);

        final afterBacks = <_Reading>[];
        for (var i = 0; i < expectedAfterBacks.length; i++) {
          await pressBrowserBack(tester);
          afterBacks.add(_shown(router, home));
        }
        printOnFailure('after each back: $afterBacks');
        expect(afterBacks, expectedAfterBacks);
      },
    );
  }
}
