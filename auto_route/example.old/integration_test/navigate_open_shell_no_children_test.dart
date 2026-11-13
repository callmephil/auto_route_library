import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// navigate() to an open page that holds a nested router, with no children,
// keeps the pages that router shows, as going back to an open screen shows
// it as it was.
// Headless test: auto_route/test/navigate_open_shell_no_children_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigate open shell no children', () {
    // Steps: open Home, push the shop with its items page, then tap 'Back to
    // the shop' on that page, which calls navigate(ShopRoute()) on the root
    // router with no children. The shop's route has no initial child.
    // Was: the shop's nested router was emptied, so the shop was blank while
    // the url still said /shop/items.
    // Should: the shop still shows its items page, at /shop/items, and back
    // shows Home.
    testWidgets('The open shop keeps its items page', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef.shell(
            name: 'ShopRoute',
            path: '/shop',
            children: [
              NamedRouteDef(
                name: 'ItemsRoute',
                path: 'items',
                builder: (context, _) => Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        const Text('ItemsRoute'),
                        TextButton(
                          onPressed: () => unawaited(
                            context.router.root.navigate(
                              const NamedRoute('ShopRoute'),
                            ),
                          ),
                          child: const Text('Back to the shop'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              NamedRouteDef(
                name: 'CartRoute',
                path: 'cart',
                builder: (_, _) =>
                    const Scaffold(body: SafeArea(child: Text('CartRoute'))),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(
        router.push(
          const NamedRoute('ShopRoute', children: [NamedRoute('ItemsRoute')]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to the shop'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ShopRoute']);
      expect(find.text('ItemsRoute'), findsOneWidget);
      expect(router.currentUrl, '/shop/items');
      await expectBrowserUrl('/shop/items');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
    });
  });
}
