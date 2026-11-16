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

// On the web, pages the app opens together in a tab, after the user changed
// to another tab and back, get their browser entries after that tab
// change. The back button closes them one by one, the page on top first,
// before it shows the other tab.
//
// Before, the entry of a page opened under the top went right after the
// entry of the nearest page under it, which could be older than the tab
// change. After tab One, tab Two, tab One and a replaceAll of X1 and Y1 in
// One, back from Y1 showed tab Two, and only the next press showed X1.
//
// The steps: Home, then the tabs on One, a change to Two and back to One,
// then a replaceAll of X1 and Y1 in One's router, then the back button
// down to Home.
//
// Native behavior this holds to: Flutter's Navigator, where Navigator.pop
// takes the top-most route only, so in the tab's stack Y1 then X1. On iOS a tab bar's
// back never changes tabs; on Android back from another top-level tab
// returns to the start destination (developer.android.com/guide/navigation/
// principles), which is a tab change. Where the platforms differ, back not
// changing tabs here is this package's own rule: the order the user went
// through, the latest first.
NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [NamedRoute('OneRoute'), NamedRoute('TwoRoute')],
        builder: (_, child) => child,
      ),
      children: [
        NamedRouteDef(
          name: 'OneRoute',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OneIndexRoute', ''),
            _page('X1Route', 'x'),
            _page('Y1Route', 'y'),
          ],
        ),
        _page('TwoRoute', 'two'),
      ],
    ),
  ],
);

// The page on top: the active tab's top page, or the root's.
String _shown(RootStackRouter router) {
  final tabs = router.innerRouterOf<TabsRouter>('TabsRoute');
  final one = tabs?.innerRouterOf<StackRouter>('OneRoute');
  final name = switch (tabs?.activeIndex) {
    0 => one?.topRoute.name,
    1 => 'TwoRoute',
    _ => router.topRoute.name,
  };
  return name?.replaceAll('Route', '') ?? 'none';
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('tab One, Two, One, then replaceAll [X1, Y1] in One', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    String reading() =>
        '(${browserSerialCount - home}, $browserPath, ${_shown(router)})';
    unawaited(router.push(const NamedRoute('TabsRoute')));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute');
    for (final index in [1, 0]) {
      tabs?.setActiveIndex(index);
      await settleBrowser(tester);
    }
    final one = tabs?.innerRouterOf<StackRouter>('OneRoute');
    unawaited(
      one?.replaceAll(const [NamedRoute('X1Route'), NamedRoute('Y1Route')]),
    );
    await settleBrowser(tester);
    final readings = [reading()];
    for (var i = 0; i < 6 && browserSerialCount > home; i++) {
      await pressBrowserBack(tester);
      readings.add(reading());
    }
    expect(readings, [
      '(3, /tabs/one/y, Y1)',
      '(2, /tabs/one/x, X1)',
      '(1, /tabs/two, Two)',
      '(0, /, Home)',
    ]);
  });
}
