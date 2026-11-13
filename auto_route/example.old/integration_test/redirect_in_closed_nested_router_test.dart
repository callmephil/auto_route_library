import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Leaving a nested router while a guard's redirect is open in it throws
// nothing, as nothing is taken off a Navigator that was disposed.
// Headless test:
// auto_route/test/guards/redirect_in_closed_nested_router_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('redirect in closed nested router', () {
    NamedRouteDef page(
      String name,
      String path, {
      List<AutoRouteGuard> guards = const [],
      PageRouteInfo? signOutTo,
    }) => .new(
      name: name,
      path: path,
      guards: guards,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Text(name),
              if (signOutTo != null)
                TextButton(
                  onPressed: () =>
                      unawaited(context.router.root.replaceAll([signOutTo])),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ),
      ),
    );

    // Steps: open Home, push the shop, push its cart, whose guard shows the
    // login page with redirectUntil in the shop's nested router. Tap
    // 'Cancel' on the login page, which leaves the shop from the root router
    // with replaceAll([WelcomeRoute]). Push Home and go back.
    // Was: "A NestedStackRouter was used after being disposed" in debug
    // builds; in release builds the next page took the welcome page's
    // history entry.
    // Should: nothing throws, the welcome page shows, and back from Home
    // shows it again.
    testWidgets('Leaving the shop from its login redirect throws nothing', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('WelcomeRoute', '/welcome'),
          NamedRouteDef.shell(
            name: 'ShopRoute',
            path: '/shop',
            children: [
              page('ItemsRoute', ''),
              page(
                'LoginRoute',
                'login',
                signOutTo: const NamedRoute('WelcomeRoute'),
              ),
              page(
                'CartRoute',
                'cart',
                guards: [
                  AutoRouteGuard.simple(
                    (resolver, _) => unawaited(
                      resolver.redirectUntil(const NamedRoute('LoginRoute')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('ShopRoute')));
      await tester.pumpAndSettle();
      final shop = router.innerRouterOf<StackRouter>('ShopRoute')!;
      unawaited(shop.push(const NamedRoute('CartRoute')));
      await tester.pumpAndSettle();
      final loginPagesShown = find.text('LoginRoute').evaluate().length;

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(loginPagesShown, 1);
      expect(router.stack.map((page) => page.name), ['WelcomeRoute']);
      expect(router.navigationHistory.isUrlStateMarkedForReplace, isFalse);
      await expectBrowserUrl('/welcome');
      final welcomePagesShown = find.text('WelcomeRoute').evaluate().length;

      unawaited(router.push(const NamedRoute('HomeRoute')));
      await tester.pumpAndSettle();
      await systemBack(tester);

      expect(router.current.name, 'WelcomeRoute');
      expect(
        (welcomePagesShown, find.text('WelcomeRoute').evaluate().length),
        (1, 1),
      );
    });
  });
}
