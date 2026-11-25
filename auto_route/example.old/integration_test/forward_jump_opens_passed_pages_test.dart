import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, a jump forward over several entries, as from the list a long
// press on the forward button shows, opens the page of each entry it passes,
// in order, as forward presses do, and changes no entry. Before, the app
// opened only the page of the entry landed on, over the page shown before:
// it stepped the browser back and pushed that url, which dropped the
// entries between and ahead (callmephil/auto_route_library#41).
// Headless tests: auto_route/test/forward_jump_opens_passed_pages_test.dart
// and auto_route/test/web/forward_jump_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// history.go(n) goes to the entry n steps away and adds or changes no entry.
// Web only: off the web there is no browser history to jump through.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a jump forward over several entries', () {
    // Steps: on Home, push A, then B. Press the browser's back button two
    // times, then jump two entries forward, onto B.
    // Was: Home and B, on a new entry after the entry of Home.
    // Should: Home, A and B, on the entry of B; back shows A, then Home.
    testWidgets(
      'onto B opens A, then B, and back shows A, then Home',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterConfigApp(tester, router.config());
        final home = browserEntryIndex()!;
        for (final name in ['ARoute', 'BRoute']) {
          unawaited(router.push(NamedRoute<Object?>(name)));
          await tester.pumpAndSettle();
        }
        await expectBrowserEntry(home + 2);
        const backWalk = [('ARoute', '/a'), ('HomeRoute', '/')];
        await expectBrowserBackWalk(tester, router, backWalk);

        await expectBrowserEntryAfter(2, () => jumpBrowser(2));
        await tester.pumpAndSettle();
        await expectBrowserUrl('/b');
        await tester.pumpAndSettle();
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'ARoute',
          'BRoute',
        ]);
        await expectBrowserBackWalk(tester, router, backWalk);
      },
      skip: !kIsWeb,
    );

    // Steps: on Home, open Store on Orders, open Order 7 in Orders, then
    // select Account. Press back three times, which closes Store, then jump
    // three entries forward, onto Account.
    // Was: Account over Home, on a new entry after the entry of Home.
    // Should: Account on its entry; back shows Order 7, OrdersIndex, Home.
    testWidgets(
      'onto Account opens OrdersIndex, Order 7, then Account',
      (tester) async {
        final router = _storeRouter();
        await pumpRouterConfigApp(tester, router.config());
        final home = browserEntryIndex()!;
        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('Store')!;
        final orders = tabs.innerRouterOf<StackRouter>('Orders')!;
        unawaited(orders.pushPath<Object?>('7'));
        await tester.pumpAndSettle();
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 3);
        const backWalk = [
          ('Order', '/store/orders/7'),
          ('OrdersIndex', '/store/orders'),
          ('Home', '/'),
        ];
        await expectBrowserBackWalk(tester, router, backWalk);

        await expectBrowserEntryAfter(3, () => jumpBrowser(3));
        await tester.pumpAndSettle();
        await expectBrowserUrl('/store/account');
        await tester.pumpAndSettle();
        expect(router.topRoute.name, 'Account');
        await expectBrowserBackWalk(tester, router, backWalk);
      },
      skip: !kIsWeb,
    );
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account; Orders holds a
// nested router with OrdersIndex and Order.
RootStackRouter _storeRouter() => .build(
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
          builder: (_, _) => const AutoRouter(),
          children: [_page('OrdersIndex', ''), _page('Order', ':id')],
        ),
        _page('Account', 'account'),
      ],
    ),
  ],
);
