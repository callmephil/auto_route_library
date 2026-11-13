import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A nested page whose path is generated, pushed from a router above its
// parent, gets a url with its own segment.
// Steps: '/shop' has the children '' (ProductsRoute) and CartRoute, which is
// given no path, so its path is generated from its name: 'cart-route'
// (README, "Paths are optional"). The app runs on '/'. Push CartRoute on the
// root router; the router adds ShopRoute around it.
// Was: the cart showed at the url /shop, the url of ProductsRoute, so a
// reload or a shared link opened the products. The router found the parents
// of a route by walking the routes as the app wrote them, while a generated
// path sits only on the copy of the route its collection keeps. Found by the
// second audit (U2-3).
// Native behavior this holds to: the url names the page on screen, however
// the page was opened: on the web the address after history.pushState loads
// the same document, and Flutter's Navigator reports the RouteSettings.name of
// the route on top whichever call pushed it.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'ShopRoute',
      path: '/shop',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'ProductsRoute',
          path: '',
          builder: (_, _) => const Text('ProductsRoute'),
        ),
        NamedRouteDef(
          name: 'CartRoute',
          builder: (_, _) => const Text('CartRoute'),
        ),
        NamedRouteDef(
          name: 'AccountRoute',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'OrdersRoute',
              builder: (_, _) => const Text('OrdersRoute'),
            ),
          ],
        ),
      ],
    ),
  ],
);

// Hands [location] to the running app the way the engine does when the
// platform opens a link.
Future<void> _sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

// The top page a reload of [url], or a link to it, opens.
String? _pageAt(String url) {
  final router = _router();
  addTearDown(router.dispose);
  return router.matcher.match(url)?.lastOrNull?.flattened.lastOrNull?.name;
}

void main() {
  testWidgets('Control: the link /shop/cart-route opens the cart', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await _sendPlatformLink(tester, '/shop/cart-route');
    await tester.pumpAndSettle();
    expect(find.text('CartRoute'), findsOneWidget);
    expect(router.currentUrl, '/shop/cart-route');
  });

  testWidgets('Control: pushed with its parent named, the cart is at '
      '/shop/cart-route', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute('ShopRoute', children: [NamedRoute('CartRoute')]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CartRoute'), findsOneWidget);
    expect(router.currentUrl, '/shop/cart-route');
  });

  testWidgets('Pushed on the root router by itself, the cart is at '
      '/shop/cart-route', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('CartRoute')));
    await tester.pumpAndSettle();
    expect(find.text('CartRoute'), findsOneWidget);
    expect(router.currentUrl, '/shop/cart-route');
  });

  testWidgets('Pushed on the root router by itself, a page two routers down '
      'is at /shop/account-route/orders-route', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('OrdersRoute')));
    await tester.pumpAndSettle();
    expect(find.text('OrdersRoute'), findsOneWidget);
    expect(router.currentUrl, '/shop/account-route/orders-route');
  });

  testWidgets('The url the cart gets opens the cart again', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('CartRoute')));
    await tester.pumpAndSettle();
    expect(find.text('CartRoute'), findsOneWidget);
    final url = router.currentUrl;

    expect(
      _pageAt(url),
      'CartRoute',
      reason: 'the url of the cart, $url, opens another page',
    );
  });
}
