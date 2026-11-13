import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// redirectUntil(replace: true) to a page that does not open leaves the page
// it would replace on the stack, as Flutter's Navigator.pushReplacement takes
// the old route off in the same step that pushes the new one.
// Headless test: auto_route/test/guards/redirect_replace_rejected_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('redirect replace rejected', () {
    // Steps: open Home, push Details. Push Account, whose guard calls
    // redirectUntil(Login, replace: true), and Login's own guard rejects it.
    // Then push Other and go back.
    // Was: Details was off the stack while still on screen, so back from
    // Other showed Home.
    // Should: Details stays, and back from Other shows it.
    testWidgets('redirectUntil(replace: true) to a rejected page keeps the '
        'page it would replace', (tester) async {
      Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'DetailsRoute',
            path: '/details',
            builder: (_, _) => page('DetailsRoute'),
          ),
          NamedRouteDef(
            name: 'OtherRoute',
            path: '/other',
            builder: (_, _) => page('OtherRoute'),
          ),
          NamedRouteDef(
            name: 'LoginRoute',
            path: '/login',
            guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
            builder: (_, _) => page('LoginRoute'),
          ),
          NamedRouteDef(
            name: 'AccountRoute',
            path: '/account',
            guards: [
              AutoRouteGuard.simple(
                (resolver, _) => unawaited(
                  resolver.redirectUntil(
                    const NamedRoute('LoginRoute'),
                    replace: true,
                  ),
                ),
              ),
            ],
            builder: (_, _) => page('AccountRoute'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();

      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();

      // Details on screen, and the pages on the stack.
      (int, int) shown() =>
          (find.text('DetailsRoute').evaluate().length, router.stack.length);
      final afterRedirect = shown();
      await expectBrowserUrl('/details');

      unawaited(router.push(const NamedRoute('OtherRoute')));
      await tester.pumpAndSettle();
      unawaited(router.maybePop());
      await tester.pumpAndSettle();

      expect((afterRedirect, shown()), ((1, 2), (1, 2)));
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'DetailsRoute',
      ]);
    });
  });
}
