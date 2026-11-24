@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, a navigation to a tab whose guard waits gives the tabs
// page one entry, also when the tabs build the tab's nested router before
// the tab shows (callmephil/auto_route_library#34). The steps, what was
// seen and what should be seen are those of the headless test on the VM:
// test/push_to_tab_with_waiting_guard_test.dart.
//
// Native behavior this holds to: one navigation adds one step back, and
// the tab that the guard lets in takes the place of the tab shown
// meanwhile, as history.replaceState writes over the current entry of the
// browser (HTML standard).

// How the tabs page builds its tabs, as in the headless test.
enum _Tabs { builder, eagerPageView, appGuard }

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

const _tabRoutes = [
  NamedRoute<Object?>('Shop'),
  NamedRoute<Object?>('Orders'),
  NamedRoute<Object?>('Account'),
];

// Home, then Store with the tabs Shop, Orders and Account, built as [tabs]
// says. Orders has a guard that waits 1 ms, then lets the tab in, and a
// nested router with OrdersIndex, whose guard says no with [refusesIndex].
RootStackRouter _storeRouter(_Tabs tabs, {bool refusesIndex = false}) => .build(
  guards: [
    if (tabs == .appGuard)
      AutoRouteGuard.simple((resolver, _) => resolver.next()),
  ],
  routes: [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => Scaffold(
        body: switch (tabs) {
          .builder => AutoTabsRouter.builder(
            routes: _tabRoutes,
            builder: (_, children, tabsRouter) =>
                IndexedStack(index: tabsRouter.activeIndex, children: children),
          ),
          .eagerPageView => const AutoTabsRouter.pageView(
            routes: _tabRoutes,
            lazyLoad: false,
          ),
          .appGuard => const AutoTabsRouter(routes: _tabRoutes),
        },
      ),
      children: [
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          guards: [
            // A sign-in check that waits, as for a token in storage.
            AutoRouteGuard.simple((resolver, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'OrdersIndex',
              path: '',
              guards: [
                if (refusesIndex)
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
              ],
              builder: (_, _) => const Text('OrdersIndex'),
            ),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  for (final tabs in _Tabs.values) {
    testWidgets('pushPath to Orders, whose guard waits, gives Store one '
        'entry, and back and forward walk Home and Orders (${tabs.name})', (
      tester,
    ) async {
      final router = _storeRouter(tabs);
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final home = browserSerialCount;
      String shown() =>
          '${router.topRoute.name} $browserPath ${browserSerialCount - home}';

      unawaited(router.pushPath<Object?>('/store/orders'));
      await settleBrowser(tester);
      // The page shown and the entry it is on: after the push, after back,
      // and after forward.
      final shownAfter = [shown()];
      await pressBrowserBack(tester);
      shownAfter.add(shown());
      await pressBrowserForward(tester);
      shownAfter.add(shown());

      expect(shownAfter, [
        'OrdersIndex /store/orders 1',
        'Home / 0',
        'OrdersIndex /store/orders 1',
      ]);
    });

    // Orders shows as soon as its own guard lets it in, and the no of the
    // guard inside it takes the new tabs page back, as a nested guard's no
    // does (callmephil/auto_route_library#33 and #45).
    testWidgets('a no of the guard inside Orders takes Store back '
        '(${tabs.name})', (tester) async {
      final router = _storeRouter(tabs, refusesIndex: true);
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);

      unawaited(router.pushPath<Object?>('/store/orders'));
      await settleBrowser(tester);

      expect(
        ('${router.topRoute.name} $browserPath', router.stack.length),
        ('Home /', 1),
      );
    });
  }
}
