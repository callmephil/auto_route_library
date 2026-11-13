import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Signing in closes the login page of a guard that awaits its redirect: the
// state decides what shows, as SwiftUI dismisses a cover presented with
// fullScreenCover(isPresented:) once its binding turns false.
// Headless test: auto_route/test/reevaluatable_router/sign_in_closes_awaited_redirect_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('sign in closes awaited redirect', () {
    // Steps: signed in, open Home and push Account, whose guard sends a
    // signed-out user to a login page and awaits that redirect. The router
    // reevaluates when the session changes. Sign out, then sign in.
    // Was: the login page stayed open after the sign-in, as the guard was
    // asked again only once its call had returned, which it does when the
    // login page closes.
    // Should: the login page closes and Account shows again.
    testWidgets('Signing in closes the login page of a guard that awaits its '
        'redirect', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) =>
          .new(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) async {
              if (isSignedIn.value) return resolver.next();
              await resolver.redirectUntil(const NamedRoute('LoginRoute'));
            }),
          ),
          page('LoginRoute', '/login'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      expectTopPage(router, 'LoginRoute');
      await expectBrowserUrl('/login');

      isSignedIn.value = true;
      await tester.pumpAndSettle();

      expect(find.text('AccountRoute'), findsOneWidget);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
      ]);
      await expectBrowserUrl('/account');
    });
  });
}
