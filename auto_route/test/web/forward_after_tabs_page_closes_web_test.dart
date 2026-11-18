@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, the forward button walks the same entries that the
// back button walked down, also after the back button closed a tabs page
// (callmephil/auto_route_library#22). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/forward_after_tabs_page_closes_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// a forward traversal moves to a later entry and changes none.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Tabs with the tabs One and Two, each with a nested router.
RootStackRouter _tabsRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [
          NamedRoute<Object?>('OneRoute'),
          NamedRoute<Object?>('TwoRoute'),
        ],
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
            _page('Z1Route', 'z'),
          ],
        ),
        NamedRouteDef(
          name: 'TwoRoute',
          path: 'two',
          builder: (_, _) => const AutoRouter(),
          children: [_page('TwoIndexRoute', '')],
        ),
      ],
    ),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('After back closed the tabs page, forward shows Two, then Z1 '
      'on its entry, and the entries stay', (tester) async {
    final router = _tabsRouter();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
    final one = tabs.innerRouterOf<StackRouter>('OneRoute')!;
    unawaited(
      one.pushAll(const [
        NamedRoute<Object?>('X1Route'),
        NamedRoute<Object?>('Y1Route'),
      ]),
    );
    await settleBrowser(tester);
    tabs.setActiveIndex(1);
    await settleBrowser(tester);
    tabs.setActiveIndex(0);
    await settleBrowser(tester);
    unawaited(one.replaceAll(const [NamedRoute<Object?>('Z1Route')]));
    await settleBrowser(tester);
    expect(browserPath, '/tabs/one/z');
    expect(browserSerialCount, home + 2);

    String shown() =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
    final walk = <String>[];
    for (final press in [
      pressBrowserBack,
      pressBrowserBack,
      pressBrowserForward,
      pressBrowserForward,
      // The entries stay the walk's: back and forward again.
      pressBrowserBack,
      pressBrowserForward,
    ]) {
      await press(tester);
      walk.add(shown());
    }
    expect(walk, [
      'TwoIndexRoute /tabs/two 1',
      'HomeRoute / 0',
      'TwoIndexRoute /tabs/two 1',
      'Z1Route /tabs/one/z 2',
      'TwoIndexRoute /tabs/two 1',
      'Z1Route /tabs/one/z 2',
    ]);
  });
}
