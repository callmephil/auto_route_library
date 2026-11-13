import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A nested page whose path is generated, pushed from the root router, gets a
// url with its own segment.
// Headless test: auto_route/test/nested_generated_path_url_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('generated nested path in the url', () {
    Widget page(String text) => Scaffold(body: SafeArea(child: Text(text)));

    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'ShopRoute',
          path: '/shop',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'ProductsRoute',
              path: '',
              builder: (_, _) => page('ProductsRoute'),
            ),
            NamedRouteDef(
              name: 'CartRoute',
              builder: (_, _) => page('CartRoute'),
            ),
          ],
        ),
      ],
    );

    // Steps: on Home, push CartRoute on the root router.
    // Was: the url was /shop.
    // Should: the cart shows at /shop/cart-route.
    testWidgets('The cart pushed from the root is at /shop/cart-route', (
      tester,
    ) async {
      final app = router();
      await pumpRouterApp(tester, app);
      unawaited(app.push(const NamedRoute('CartRoute')));
      await tester.pumpAndSettle();

      expect(
        (find.text('CartRoute').evaluate().length, app.currentUrl),
        (1, '/shop/cart-route'),
      );
      await expectBrowserUrl('/shop/cart-route');
    });
  });
}
