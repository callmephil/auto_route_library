import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, back() into another tab asks only the guards of that tab, as
// the app's own tab change does, and no guard of a page that is still open.
// Before, it asked the guards of the tabs page and of the page open in the
// tab again, the global guard of each included
// (callmephil/auto_route_library#42).
// Headless test:
// auto_route/test/back_into_other_tab_asks_only_tab_guards_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.pop asks nothing of the
// route under it, and UITabBarController shows the stack of the selected tab
// as it is. Off the web only: on the web, back() is the browser's own back
// step, as in browser_back_to_open_page_asks_no_guard_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back into another tab', () {
    // Steps: on Home, open Store on its Orders tab, whose guard waits 1 ms.
    // Open Order 7 in Orders, select Account, and call back(). Then select
    // Account again, and Orders.
    // Was: back() asked the global guard and the guard of Store, the guard
    // of Orders, then the global guard and the guard of Order 7.
    // Should: back() and the tab change ask only the guard of Orders, and
    // both show Order 7.
    testWidgets(
      'back() into another tab asks only the guard of the tab',
      (tester) async {
        final asked = <String>[];
        final router = _router(asked);
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('StoreRoute')!;
        unawaited(
          tabs.innerRouterOf<StackRouter>('OrdersTab')!.pushPath<Object?>('7'),
        );
        await tester.pumpAndSettle();
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();

        Future<(String, String)> after(VoidCallback step) async {
          asked.clear();
          step();
          await tester.pumpAndSettle();
          return (router.topRoute.name, asked.join(', '));
        }

        final afterBack = await after(router.back);
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        final afterTabChange = await after(() => tabs.setActiveIndex(1));

        const onOrder = ('OrderRoute', 'OrdersTab');
        expect(tester.takeException(), isNull);
        expect(find.text('OrderRoute').hitTestable(), findsOneWidget);
        expect((afterBack, afterTabChange), (onOrder, onOrder));
      },
      skip: kIsWeb,
    );
  });
}

// Home, then Store with the tabs Shop, Orders and Account. Every stack route
// has the global guard, and Store and Order a guard of their own. Each guard
// adds its route to [asked], the global guard as 'global' and the route.
RootStackRouter _router(List<String> asked) {
  AutoRouteGuard noting(String name) => .simple((resolver, _) {
    asked.add(name);
    resolver.next();
  });
  NamedRouteDef page(String name, String path, {bool isGuarded = false}) =>
      .new(
        name: name,
        path: path,
        guards: [if (isGuarded) noting(name)],
        builder: (_, _) => Text(name),
      );

  return .build(
    guards: [
      AutoRouteGuard.simple((resolver, _) {
        asked.add('global ${resolver.routeName}');
        resolver.next();
      }),
    ],
    routes: [
      page('HomeRoute', '/'),
      NamedRouteDef(
        name: 'StoreRoute',
        path: '/store',
        guards: [noting('StoreRoute')],
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
          page('ShopTab', 'shop'),
          NamedRouteDef(
            name: 'OrdersTab',
            path: 'orders',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                asked.add('OrdersTab');
                await Future<void>.delayed(const Duration(milliseconds: 1));
                resolver.next();
              }),
            ],
            builder: (_, _) => const AutoRouter(),
            children: [
              page('OrdersIndexRoute', ''),
              page('OrderRoute', ':id', isGuarded: true),
            ],
          ),
          page('AccountTab', 'account'),
        ],
      ),
    ],
  );
}
