import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard asked again that returns without an answer holds no later change
// up: the next change still asks the guards of the pages on the stack, as
// Flutter's Router drops an older route transaction once newer route
// information arrives.
// Headless test:
// auto_route/test/reevaluatable_router/guard_lets_go_keeps_router_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('guard lets go keeps router', () {
    // Steps: open Home, Premium and Account. Premium's guard lets a premium
    // user through; Account's guard lets a signed-in user through and has
    // no else. The user signs out, then premium ends.
    // Was: Premium stayed on screen for a user who was no longer premium:
    // no change after the sign-out asked any guard of the router.
    // Should: Premium closes and Home shows.
    testWidgets('A later change closes a page whose guard now rejects', (
      tester,
    ) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final isPremium = ValueNotifier(true);
      addTearDown(isPremium.dispose);
      final session = Listenable.merge([isSignedIn, isPremium]);
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page(
            'PremiumRoute',
            '/premium',
            AutoRouteGuard.simple(
              (resolver, _) =>
                  isPremium.value ? resolver.next() : resolver.reject(),
            ),
          ),
          page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) resolver.next();
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      for (final name in ['PremiumRoute', 'AccountRoute']) {
        unawaited(router.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      expectTopPage(router, 'PremiumRoute');
      isPremium.value = false;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(router.activeGuardObserver.guardInProgress, isFalse);
      await expectBrowserUrl('/');
    });
  });
}
