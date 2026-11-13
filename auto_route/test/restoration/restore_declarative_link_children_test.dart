// Flutter's state restoration doesn't run on the web.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'restoration_test_utils.dart';

// After state restoration, a router built by AutoRouter.declarative was
// handed the pages of the link that first opened its page, although the
// app's list had changed since, so a cart the user closed was open again.
// Found by the second audit of auto_route/lib (finding W2-1).
// Cause: _savedRoute (routes_restoration.dart) saved null as the children of
// a declarative page, meaning "save none", but _savedMatch read null as "not
// given" and saved the children the page's route was matched with, the
// link's pages, which never change afterwards. On restore they became the
// page's pending children, and the routes callback took them as a new link.
// Setup: '/shop' holds AutoRouter.declarative with the products at '' and
// the cart at 'cart'. The shop keeps "the cart is open" in a RestorableBool,
// and its routes callback opens the cart for a link that names it, through
// handler.initialPendingRoutes, as the README says.
// Steps: open '/shop/cart', press back (the cart closes, onPopRoute clears
// the flag), let the platform end the app, restore it.
// Was: the cart was open again, and the shop's saved route named the cart.
// Should: the shop shows its products, as when the app was ended. Flutter's
// Router restores the route information it reported last, not the one the
// app started with (widgets/router.dart, _RestorableRouteInformation), and
// the app's own restored state decides a declarative router's pages.
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

RootStackRouter _buildRouter() => .build(
  routes: [
    AutoRoute(path: '/', page: page('HomeRoute'), initial: true),
    AutoRoute(
      path: '/shop',
      page: PageInfo('ShopRoute', builder: (_) => const _ShopPage()),
      children: [
        AutoRoute(path: '', page: page('ProductsRoute')),
        AutoRoute(path: 'cart', page: page('CartRoute')),
      ],
    ),
  ],
);

// Opens the shop at its cart by a link and closes the cart with back.
Future<void> _openCartByLinkAndClose(WidgetTester tester) async {
  await tester.pumpWidget(const RestorableRouterApp(_buildRouter));
  await tester.pumpAndSettle();
  final router = RestorableRouterApp.router;
  unawaited(router.pushPath('/shop/cart'));
  await tester.pumpAndSettle();
  final cartsOpen = find.text('CartRoute').evaluate().length;
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect((cartsOpen, find.text('CartRoute').evaluate().length), (1, 0));
  expect(router.currentUrl, '/shop');
}

void main() {
  testWidgets(
    'A restored declarative router shows the pages of the restored app '
    'state, not those of the link that first opened its page',
    (tester) async {
      await _openCartByLinkAndClose(tester);

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final router = RestorableRouterApp.router;
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ShopRoute']);
      expect(find.text('CartRoute'), findsNothing);
      expect(find.text('ProductsRoute'), findsOneWidget);
      expect(router.currentUrl, '/shop');
    },
  );

  testWidgets(
    'What a router saves for a declarative page names none of its pages',
    (tester) async {
      await _openCartByLinkAndClose(tester);

      final configuration = RestorableRouterApp.router
          .delegate()
          .currentConfiguration!;
      final saved =
          (configuration.savedRoutes! as Map)['routes'] as List<Object?>;
      expect(saved, [
        {'name': 'HomeRoute'},
        {'name': 'ShopRoute'},
      ]);
    },
  );

  // Control: the shop opened without a link comes back at its products.
  testWidgets('A shop opened by the app comes back at its products', (
    tester,
  ) async {
    await tester.pumpWidget(const RestorableRouterApp(_buildRouter));
    await tester.pumpAndSettle();
    unawaited(RestorableRouterApp.router.pushPath('/shop'));
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CartRoute'), findsNothing);
    expect(find.text('ProductsRoute'), findsOneWidget);
  });
}
