import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A RedirectRoute whose target is only partly matched opens what that target
// opens by itself: the catch-all page, not the page of its first segments.
// Headless test: auto_route/test/redirect_partly_matched_target_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('redirect to a partly matched path', () {
    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
        ),
        NamedRouteDef(
          name: 'DashRoute',
          path: '/dash',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'UsersRoute',
              path: 'users',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('UsersRoute'))),
            ),
            RedirectRoute(path: 'legacy', redirectTo: 'users/5'),
          ],
        ),
        NamedRouteDef(
          name: 'NotFoundRoute',
          path: '*',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('NotFoundRoute'))),
        ),
      ],
    );

    // Steps: start the app at the link '/dash/legacy'. It redirects to
    // '/dash/users/5', a path no page has.
    // Was: the users page showed.
    // Should: the catch-all page shows, as it does for /dash/users/5.
    testWidgets('An app started at /dash/legacy shows the catch-all page', (
      tester,
    ) async {
      final app = router();
      await pumpAppAtDeepLink(
        tester,
        '/dash/legacy',
        // Made inside the app, so the config reads the link.
        Builder(builder: (_) => MaterialApp.router(routerConfig: app.config())),
      );

      expect(
        (
          find.text('NotFoundRoute').evaluate().length,
          find.text('UsersRoute').evaluate().length,
        ),
        (1, 0),
      );
    });
  });
}
