@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, the back button after a tab change returns through
// each page once, also when the guard of the tab it goes back into waits
// (callmephil/auto_route_library#31). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/back_after_tab_change_with_waiting_guard_test.dart. The second run
// adds a guard of Order that waits too, which the back press into Orders
// asks again in the tab's nested router.
//
// Native behavior this holds to: the HTML standard's session history, where
// a back or forward traversal moves to another entry and adds none, and
// each entry stays the page the user saw there.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account; Orders holds a
// nested router and a guard that waits 1 ms, then lets the tab in. With
// [orderWaits], Order has a guard of its own that waits 1 ms too.
RootStackRouter _storeRouter({required bool orderWaits}) => .build(
  routes: [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('Shop'),
            NamedRoute<Object?>('Orders'),
            NamedRoute<Object?>('Account'),
          ],
        ),
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
            _page('OrdersIndex', ''),
            NamedRouteDef(
              name: 'Order',
              path: ':id',
              guards: [
                // A check of the order's own, such as for its owner.
                if (orderWaits)
                  AutoRouteGuard.simple((resolver, _) async {
                    await Future<void>.delayed(const Duration(milliseconds: 1));
                    resolver.next();
                  }),
              ],
              builder: (_, _) => const Text('Order'),
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

  for (final orderWaits in [false, true]) {
    testWidgets('Back after a tab change shows Order 7, OrdersIndex, then '
        'Home, and forward walks back to Account'
        '${orderWaits ? ', with a guard of Order that waits too' : ''}', (
      tester,
    ) async {
      final router = _storeRouter(orderWaits: orderWaits);
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final home = browserSerialCount;
      unawaited(router.pushPath<Object?>('/store/orders'));
      await settleBrowser(tester);
      final tabs = router.innerRouterOf<TabsRouter>('Store')!;
      unawaited(
        tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
      );
      await settleBrowser(tester);
      tabs.setActiveIndex(2);
      await settleBrowser(tester);
      expect(browserPath, '/store/account');
      expect(browserSerialCount, home + 3);

      String shown() =>
          '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
      final backWalk = <String>[];
      // At most 8 presses: before the fix, the walk took 8.
      for (var i = 0; i < 8 && browserSerialCount > home; i++) {
        await pressBrowserBack(tester);
        backWalk.add(shown());
      }
      expect(backWalk, [
        'Order /store/orders/7 2',
        'OrdersIndex /store/orders 1',
        'Home / 0',
      ]);

      final forwardWalk = <String>[];
      for (var i = 0; i < 3; i++) {
        await pressBrowserForward(tester);
        forwardWalk.add(shown());
      }
      expect(forwardWalk, [
        'OrdersIndex /store/orders 1',
        'Order /store/orders/7 2',
        'Account /store/account 3',
      ]);
    });
  }
}
