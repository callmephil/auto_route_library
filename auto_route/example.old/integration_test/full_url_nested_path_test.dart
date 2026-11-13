import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A url with a scheme and host given to navigatePath opens a nested page.
// Headless test: auto_route/test/full_url_nested_path_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('full url to a nested page', () {
    // Steps: open Home, navigatePath('https://example.com/dashboard/users').
    // Was: RouteNotFoundFailure, and Home stayed.
    // Should: Users shows, at /dashboard/users.
    testWidgets('navigatePath with a host opens a nested page', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'DashboardRoute',
            path: '/dashboard',
            builder: (_, _) => const AutoRouter(),
            children: [
              NamedRouteDef(
                name: 'OverviewRoute',
                path: '',
                builder: (_, _) => const Scaffold(
                  body: SafeArea(child: Text('OverviewRoute')),
                ),
              ),
              NamedRouteDef(
                name: 'UsersRoute',
                path: 'users',
                builder: (_, _) =>
                    const Scaffold(body: SafeArea(child: Text('UsersRoute'))),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      NavigationFailure? failure;
      unawaited(
        router.navigatePath(
          'https://example.com/dashboard/users',
          onFailure: (value) => failure = value,
        ),
      );
      await tester.pumpAndSettle();

      expect(failure, isNull);
      expect(find.text('UsersRoute'), findsOneWidget);
      expect(router.currentUrl, '/dashboard/users');
      await expectBrowserUrl('/dashboard/users');
    });
  });
}
