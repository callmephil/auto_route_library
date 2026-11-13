import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/restorable_app.dart';

// A restored AutoRouter.declarative shows the pages of the app's restored
// state, not those of the link that first opened its page.
// Headless test: auto_route/test/restoration/restore_declarative_link_children_test.dart
//
// WidgetTester.restartAndRestore ends the app's widget tree and starts it
// again from the data Flutter saved for restoration, which is what the
// platform hands back to an app it ended. A new router is built.
class _ShopPage extends StatefulWidget {
  const new();

  @override
  State<_ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<_ShopPage> with RestorationMixin {
  new();

  final _showsCart = RestorableBool(false);

  @override
  String get restorationId => 'shop_page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) =>
      registerForRestoration(_showsCart, 'shows_cart');

  @override
  void dispose() {
    _showsCart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AutoRouter.declarative(
    routes: (handler) {
      // A link that names the cart opens it.
      final linked = handler.initialPendingRoutes;
      if (linked != null && linked.any((r) => r.routeName == 'CartRoute')) {
        _showsCart.value = true;
      }
      return [
        const NamedRoute('ProductsRoute'),
        if (_showsCart.value) const NamedRoute('CartRoute'),
      ];
    },
    onPopRoute: (_, _) => setState(() => _showsCart.value = false),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('restore declarative link children', () {
    // Flutter's state restoration doesn't run on the web, so the routers save
    // their pages only off the web.
    RootStackRouter buildRouter() => .build(
      routes: [
        AutoRoute(path: '/', page: namedPage('HomeRoute'), initial: true),
        AutoRoute(
          path: '/shop',
          page: PageInfo('ShopRoute', builder: (_) => const _ShopPage()),
          children: [
            AutoRoute(path: '', page: namedPage('ProductsRoute')),
            AutoRoute(path: 'cart', page: namedPage('CartRoute')),
          ],
        ),
      ],
    );

    // Steps: a link opens the shop at its cart, back closes the cart, and
    // the platform ends the app and restores it.
    // Was: the cart was open again.
    // Should: the shop shows its products, as Flutter's Router restores the
    // route information it reported last, not the one the app started with.
    testWidgets('a cart closed before the app ended stays closed', (
      tester,
    ) async {
      await pumpRestorableApp(tester, buildRouter);
      var router = RestorableRouterApp.router;
      unawaited(router.pushPath('/shop/cart'));
      await tester.pumpAndSettle();
      final cartsOpen = find.text('CartRoute').evaluate().length;
      await systemBack(tester);
      expect((cartsOpen, find.text('CartRoute').evaluate().length), (1, 0));

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      router = RestorableRouterApp.router;
      expect(find.text('CartRoute'), findsNothing);
      expect(find.text('ProductsRoute'), findsOneWidget);
      expect(router.currentPath, '/shop');
    }, skip: kIsWeb);
  });
}
