import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Steps: open the app at '/protected', which a guard says no to, with no page
// of the app below it (a browser opens a link alone). A: the guard is a
// global guard (RootStackRouter.guards). B: the first page, Home, has a guard
// of its own that sends the user to Login.
// Should: A shows Home, and the global guard is asked once for each route.
// B shows Login, as the guard of Home decides. Before, the screen was empty.
// Native behavior: Flutter's Navigator.pages refuses an empty list, and a
// Navigator with no route opens its default route '/'; Android's NavController
// always has its start destination (developer.android.com/guide/navigation/
// backstack, "Handle a failed pop back"); an iOS navigation controller keeps
// its root view controller; a browser keeps the document on screen when a
// navigation is canceled.
// Headless test: auto_route/test/guards/rejected_launch_shows_first_page_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> launchAtProtected(
    WidgetTester tester,
    RootStackRouter router,
  ) => pumpAppAtDeepLink(
    tester,
    '/protected',
    MaterialApp.router(
      routerConfig: router.config(
        includePrefixMatches: false,
        // Off the web the test app can't be launched at a link, so the app is
        // told it was: the launch link of every platform.
        deepLinkBuilder: (_) =>
            const DeepLink.path('/protected', includePrefixMatches: false),
      ),
    ),
  );

  testWidgets('A launch link a global guard rejected opens the first page', (
    tester,
  ) async {
    final asked = <String>[];
    final router = RootStackRouter.build(
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          asked.add(resolver.routeName);
          if (resolver.routeName == 'ProtectedRoute') {
            return resolver.reject();
          }
          resolver.next();
        }),
      ],
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('Home'),
        ),
        NamedRouteDef(
          name: 'ProtectedRoute',
          path: '/protected',
          builder: (_, _) => const Text('Protected'),
        ),
      ],
    );
    await launchAtProtected(tester, router);
    expect(router.stack.map((page) => page.name), ['HomeRoute']);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Protected'), findsNothing);
    expect(asked, ['ProtectedRoute', 'HomeRoute']);
    await expectBrowserUrl('/');
  });

  testWidgets('A rejected launch link shows what the first page guard says', (
    tester,
  ) async {
    var homeAsks = 0;
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          guards: [
            AutoRouteGuard.simple((resolver, _) {
              homeAsks++;
              unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
            }),
          ],
          builder: (_, _) => const Text('Home'),
        ),
        NamedRouteDef(
          name: 'ProtectedRoute',
          path: '/protected',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
          builder: (_, _) => const Text('Protected'),
        ),
        NamedRouteDef(
          name: 'LoginRoute',
          path: '/login',
          builder: (_, _) => const Text('Login'),
        ),
      ],
    );
    await launchAtProtected(tester, router);
    expect(router.stack.map((page) => page.name), ['LoginRoute']);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(homeAsks, 1);
    await expectBrowserUrl('/login');
  });
}
