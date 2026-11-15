import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The pages that replaceAll set aside for a guard's page are asked as they
// come back when the session changed meanwhile, as an app checks the session
// again where UIKit calls viewWillAppear and Android calls onResume on a
// screen that comes back to the top.
// Headless test: auto_route/test/reevaluatable_router/set_aside_page_asked_when_back_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('set aside page asked when back', () {
    // Steps: signed in on Account, over Home. The app replaces the pages
    // with Vault, whose guard sends a locked user to a pin page: the pin
    // page shows alone. The session ends. The user cancels the pin page.
    // Was: Account was back on screen for the signed-out user.
    // Should: Home shows, and Account is closed.
    testWidgets('A page a guard of replaceAll set aside is asked as it '
        'comes back when the session ended meanwhile', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final locking = <NavigationResolver>[];
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
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple(
              (resolver, _) =>
                  isSignedIn.value ? resolver.next() : resolver.reject(),
            ),
          ),
          page(
            'VaultRoute',
            '/vault',
            AutoRouteGuard.simple((resolver, _) {
              if (resolver.isReevaluating) return;
              locking.add(resolver);
              unawaited(resolver.redirectUntil(const NamedRoute('PinRoute')));
            }),
          ),
          page('PinRoute', '/pin'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      final failures = <NavigationFailure>[];
      unawaited(
        router.replaceAll([
          const NamedRoute('VaultRoute'),
        ], onFailure: failures.add),
      );
      await tester.pumpAndSettle();
      expectTopPage(router, 'PinRoute');

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      locking.singleOrNull?.reject();
      await tester.pumpAndSettle();

      expectTopPage(router, 'HomeRoute');
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('AccountRoute'), findsNothing);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      await expectBrowserUrl('/');
    });
  });
}
