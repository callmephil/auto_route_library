import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
import '../router_test_utils.dart';

// Once the list of a router built by AutoRouter.declarative changed, the
// nested router inside a page that stays was cut off from the router tree:
// the url, topRoute, canPop and topMostRouter no longer saw its pages, though
// they were still on screen, and a page it opened read the old path params of
// its host. Found by the audit of auto_route/lib at dev 56b73492 (finding W1).
// Cause: StackRouter.updateDeclarativeRoutes built every page of the list with
// a new match id, also a page the navigator keeps and updates in place, while
// a router finds the nested router of a page by the page's match id.
// Steps: a host page builds AutoRouter.declarative with [ShopRoute, if
// (showsSettings) SettingsRoute]; ShopRoute holds a nested router with a
// products page and a cart page. Open the cart, show the settings, press
// back, and onPopRoute clears showsSettings.
// Was: the cart showed, but the url was /shop, topRoute was ShopRoute and
// canPop() was false.
// Should: the cart shows, the url is /shop/cart, topRoute is CartRoute and
// canPop() is true, as before the settings showed. Flutter's Navigator keeps
// the route and the state of a page it updates in place (Page.canUpdate), so
// the nested navigator and its pages stay; on the web the address names the
// page on screen, and context.topRoute is "the top most rendered route".
void main() {
  testWidgets(
    'The pages of a nested router stay in the url and the router tree when '
    'the declarative list around them changes',
    (tester) async {
      final showsSettings = ValueNotifier(false);
      addTearDown(showsSettings.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HostRoute',
            path: '/',
            builder: (_, _) => ValueListenableBuilder(
              valueListenable: showsSettings,
              builder: (context, isShown, _) => AutoRouter.declarative(
                routes: (_) => [
                  const NamedRoute('ShopRoute'),
                  if (isShown) const NamedRoute('SettingsRoute'),
                ],
                onPopRoute: (_, _) => showsSettings.value = false,
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'ShopRoute',
                path: 'shop',
                builder: (_, _) => const AutoRouter(),
                children: [
                  NamedRouteDef(
                    name: 'ProductsRoute',
                    path: '',
                    builder: (_, _) => const Scaffold(body: Text('Products')),
                  ),
                  NamedRouteDef(
                    name: 'CartRoute',
                    path: 'cart',
                    builder: (_, _) => const Scaffold(body: Text('Cart')),
                  ),
                ],
              ),
              NamedRouteDef(
                name: 'SettingsRoute',
                path: 'settings',
                builder: (_, _) => const Scaffold(body: Text('Settings')),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      final declarative = router.innerRouterOf<StackRouter>('HostRoute')!;
      final shop = declarative.innerRouterOf<StackRouter>('ShopRoute')!;
      unawaited(shop.push(const NamedRoute('CartRoute')));
      await tester.pumpAndSettle();
      final cartsBefore = find.text('Cart').evaluate().length;
      final topBefore = router.topRoute.name;
      final urlBefore = router.currentUrl;
      final couldPopBefore = router.canPop();

      showsSettings.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await systemBack(tester);

      // The shop page kept its state: the cart is on screen again.
      expect((cartsBefore, find.text('Cart').evaluate().length), (1, 1));
      expect(shop.stack.map((page) => page.name), [
        'ProductsRoute',
        'CartRoute',
      ]);
      expect((topBefore, router.topRoute.name), ('CartRoute', 'CartRoute'));
      expect((urlBefore, router.currentUrl), ('/shop/cart', '/shop/cart'));
      expect((couldPopBefore, router.canPop()), (true, true));
      expect(router.topMostRouter(), shop);
    },
  );

  // The same cut, seen as wrong data: the nested router kept the route data
  // of the page as it was before the list changed, so a page it opened later
  // inherited the old path param (README, "Inherited Path Parameters").
  // Steps: the declarative list is [ShopRoute(storeId)], as in #2125's
  // `routes: (_) => [HomeRoute(id: id)]`; ShopRoute holds a nested router.
  // Change storeId from 1 to 2, then open the cart in the nested router.
  // Was: the shop page showed store 2, the cart page said store 1, and the
  // url was /shop/2, without the cart.
  // Should: the cart reads store 2 and the url is /shop/2/cart.
  testWidgets(
    'A page opened in the nested router after the declarative list changed '
    "its host's path param inherits the new param",
    (tester) async {
      final storeId = ValueNotifier(1);
      addTearDown(storeId.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HostRoute',
            path: '/',
            builder: (_, _) => ValueListenableBuilder(
              valueListenable: storeId,
              builder: (context, id, _) => AutoRouter.declarative(
                routes: (_) => [
                  NamedRoute('ShopRoute', params: {'storeId': id}),
                ],
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'ShopRoute',
                path: 'shop/:storeId',
                builder: (_, data) => Column(
                  children: [
                    Text('Shop ${data.params.getInt('storeId')}'),
                    const Expanded(child: AutoRouter()),
                  ],
                ),
                children: [
                  NamedRouteDef(
                    name: 'ProductsRoute',
                    path: '',
                    builder: (_, _) => const Text('Products'),
                  ),
                  NamedRouteDef(
                    name: 'CartRoute',
                    path: 'cart',
                    builder: (_, data) => Text(
                      'Cart of store '
                      '${data.inheritedPathParams.getInt('storeId')}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      final declarative = router.innerRouterOf<StackRouter>('HostRoute')!;
      final shop = declarative.innerRouterOf<StackRouter>('ShopRoute')!;
      expect(find.text('Shop 1'), findsOneWidget);
      expect(router.currentUrl, '/shop/1');

      storeId.value = 2;
      await tester.pumpAndSettle();
      // The shop page is updated in place.
      expect(find.text('Shop 2'), findsOneWidget);
      expect(declarative.innerRouterOf<StackRouter>('ShopRoute'), same(shop));

      unawaited(shop.push(const NamedRoute('CartRoute')));
      await tester.pumpAndSettle();
      expect(find.text('Cart of store 1'), findsNothing);
      expect(find.text('Cart of store 2'), findsOneWidget);
      expect(router.currentUrl, '/shop/2/cart');
    },
  );
}
