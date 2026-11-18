import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, the browser's back button after a tab change returns through
// each page once, also when the guard of the tab it goes back into waits.
// Before, the app took the entry of the page in that tab for a link it had
// turned down while the guard still decided, wrote the url of the tab on
// screen over it and moved the browser forward: 8 presses, with the page in
// the guarded tab lost (callmephil/auto_route_library#31).
// Headless tests:
// auto_route/test/back_after_tab_change_with_waiting_guard_test.dart and
// auto_route/test/web/back_after_tab_change_with_waiting_guard_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where a back traversal moves to the entry before and adds none, and each
// entry stays the page the user saw there. Web only: off the web there is
// no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after a tab change, the tab guard waits', () {
    // Steps: on Home, open Store on its Orders tab, whose guard waits 1 ms.
    // Open Order 7 in Orders, then select the Account tab. Press the
    // browser's back button until Home, then its forward button until
    // Account.
    // Was: 8 back presses; two moved the browser forward.
    // Should: back shows Order 7, Orders, then Home, one entry each, and
    // forward walks the same entries up to Account. Also with a guard of
    // Order that waits too, which the back press into Orders asks again.
    for (final orderWaits in [false, true]) {
      testWidgets(
        'Back shows Order 7, Orders, then Home'
        '${orderWaits ? ', with a guard of Order that waits too' : ''}',
        (tester) async {
          final router = _storeRouter(orderWaits: orderWaits);
          await pumpRouterConfigApp(tester, router.config());
          final home = browserEntryIndex()!;

          unawaited(router.pushPath<Object?>('/store/orders'));
          await tester.pumpAndSettle();
          final tabs = router.innerRouterOf<TabsRouter>('StoreRoute')!;
          unawaited(
            tabs
                .innerRouterOf<StackRouter>('OrdersTab')!
                .pushPath<Object?>('7'),
          );
          await tester.pumpAndSettle();
          tabs.setActiveIndex(2);
          await tester.pumpAndSettle();
          await expectBrowserEntry(home + 3);
          await expectBrowserUrl('/store/account');

          await expectBrowserBackWalk(tester, router, [
            ('OrderRoute', '/store/orders/7'),
            ('OrdersIndexRoute', '/store/orders'),
            ('HomeRoute', '/'),
          ]);

          for (final (name, url) in [
            ('OrdersIndexRoute', '/store/orders'),
            ('OrderRoute', '/store/orders/7'),
            ('AccountTab', '/store/account'),
          ]) {
            await expectBrowserEntryAfter(1, pressBrowserForward);
            await tester.pumpAndSettle();
            await expectBrowserUrl(url);
            expect(router.topRoute.name, name, reason: 'after forward to $url');
          }
        },
        skip: !kIsWeb,
      );
    }
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// With [orderWaits], Order has a guard of its own that waits 1 ms.
RootStackRouter _storeRouter({required bool orderWaits}) => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'StoreRoute',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('ShopTab'),
            NamedRoute<Object?>('OrdersTab'),
            NamedRoute<Object?>('AccountTab'),
          ],
        ),
      ),
      children: [
        _page('ShopTab', 'shop'),
        NamedRouteDef(
          name: 'OrdersTab',
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
            _page('OrdersIndexRoute', ''),
            NamedRouteDef(
              name: 'OrderRoute',
              path: ':id',
              guards: [
                // A check of the order's own, such as for its owner.
                if (orderWaits)
                  AutoRouteGuard.simple((resolver, _) async {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 1),
                    );
                    resolver.next();
                  }),
              ],
              builder: (_, _) => const Text('OrderRoute'),
            ),
          ],
        ),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);
