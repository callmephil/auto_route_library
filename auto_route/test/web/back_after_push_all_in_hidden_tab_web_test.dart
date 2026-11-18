@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, the back button after pushAll in a tab not on screen
// shows each page once and never moves the browser forward
// (callmephil/auto_route_library#21). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/back_after_push_all_in_hidden_tab_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.pop in the router of
// the tab closes Y1, then X1. In the HTML standard's session history, a
// back or forward traversal moves to another entry and adds or changes
// none.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Tabs with the tabs One and Two, each with a nested router: One
// with OneIndex, X1 and Y1, Two with TwoIndex.
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

  testWidgets('Back after pushAll in a tab not on screen shows X1, Two, '
      'OneIndex, then Home, and forward walks back to Y1', (tester) async {
    final router = _tabsRouter();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
      ..setActiveIndex(1);
    await settleBrowser(tester);
    unawaited(
      tabs.innerRouterOf<StackRouter>('OneRoute')!.pushAll(const [
        NamedRoute<Object?>('X1Route'),
        NamedRoute<Object?>('Y1Route'),
      ]),
    );
    await settleBrowser(tester);
    tabs.setActiveIndex(0);
    await settleBrowser(tester);
    expect(browserPath, '/tabs/one/y');
    expect(browserSerialCount, home + 4);

    String shown() =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
    final backWalk = <String>[];
    // At most 6 presses: before the fix, the walk took 6.
    for (var i = 0; i < 6 && browserSerialCount > home; i++) {
      await pressBrowserBack(tester);
      backWalk.add(shown());
    }
    expect(backWalk, [
      'X1Route /tabs/one/x 3',
      'TwoIndexRoute /tabs/two 2',
      'OneIndexRoute /tabs/one 1',
      'HomeRoute / 0',
    ]);

    final forwardWalk = <String>[];
    for (var i = 0; i < 4; i++) {
      await pressBrowserForward(tester);
      forwardWalk.add(shown());
    }
    expect(forwardWalk, [
      'OneIndexRoute /tabs/one 1',
      'TwoIndexRoute /tabs/two 2',
      'X1Route /tabs/one/x 3',
      'Y1Route /tabs/one/y 4',
    ]);
  });
}
