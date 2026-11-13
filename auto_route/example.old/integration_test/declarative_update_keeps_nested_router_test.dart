import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The nested router inside a page of AutoRouter.declarative stays part of the
// router tree when the declarative list around it changes.
// Headless test: auto_route/test/nested_router/declarative_update_keeps_nested_router_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('declarative update keeps nested router', () {
    // Steps: a host page builds AutoRouter.declarative with [ShopRoute, if
    // (showsSettings) SettingsRoute]; ShopRoute holds a nested router. Tap
    // 'Open cart', tap 'Show settings', then go back.
    // Was: the cart showed, but the url was /shop and the router's top route
    // was ShopRoute.
    // Should: the url is /shop/cart and the top route is CartRoute, as
    // Flutter's Navigator keeps the route and state of a page it updates in
    // place, and the address names the page on screen.
    testWidgets('the cart stays in the url after the settings close', (
      tester,
    ) async {
      final showsSettings = ValueNotifier(false);
      addTearDown(showsSettings.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HostRoute',
            path: '/',
            builder: (_, _) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () => showsSettings.value = true,
                      child: const Text('Show settings'),
                    ),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: showsSettings,
                        builder: (_, isShown, _) => AutoRouter.declarative(
                          routes: (_) => [
                            const NamedRoute('ShopRoute'),
                            if (isShown) const NamedRoute('SettingsRoute'),
                          ],
                          onPopRoute: (_, _) => showsSettings.value = false,
                        ),
                      ),
                    ),
                  ],
                ),
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
                    builder: (context, _) => Material(
                      child: TextButton(
                        onPressed: () => context.router.push(
                          const NamedRoute('CartRoute'),
                        ),
                        child: const Text('Open cart'),
                      ),
                    ),
                  ),
                  NamedRouteDef(
                    name: 'CartRoute',
                    path: 'cart',
                    builder: (_, _) => const Material(child: Text('Cart')),
                  ),
                ],
              ),
              NamedRouteDef(
                name: 'SettingsRoute',
                path: 'settings',
                builder: (_, _) => const Material(child: Text('Settings')),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      await tester.tap(find.text('Open cart'));
      await tester.pumpAndSettle();
      final cartsBefore = find.text('Cart').evaluate().length;
      await expectBrowserUrl('/shop/cart');

      await tester.tap(find.text('Show settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await expectBrowserUrl('/settings');

      await systemBack(tester);
      expect(find.text('Settings'), findsNothing);
      expect((cartsBefore, find.text('Cart').evaluate().length), (1, 1));
      expect(router.topRoute.name, 'CartRoute');
      expect(router.currentUrl, '/shop/cart');
      await expectBrowserUrl('/shop/cart');
    });
  });
}
