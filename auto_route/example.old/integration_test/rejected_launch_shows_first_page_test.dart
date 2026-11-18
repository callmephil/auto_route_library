import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Steps: open the app at '/protected', whose guard says no, with no page of
// the app below it (a browser opens a link alone).
// Should: the first page of the app, Home, shows and the address bar is '/';
// before, the screen was empty.
// Native behavior: Flutter's Navigator.pages refuses an empty list, and a
// Navigator with no route opens its default route '/'; Android's NavController
// always has its start destination (developer.android.com/guide/navigation/
// backstack, "Handle a failed pop back"); an iOS navigation controller keeps
// its root view controller; a browser keeps the document on screen when a
// navigation is canceled.
// Headless test: auto_route/test/guards/rejected_launch_shows_first_page_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A launch link a guard rejected opens the first page', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('Home'),
        ),
        NamedRouteDef(
          name: 'ProtectedRoute',
          path: '/protected',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
          builder: (_, _) => const Text('Protected'),
        ),
      ],
    );
    await pumpAppAtDeepLink(
      tester,
      '/protected',
      MaterialApp.router(
        routerConfig: router.config(
          includePrefixMatches: false,
          // Off the web the test app can't be launched at a link, so the
          // app is told it was: the launch link of every platform.
          deepLinkBuilder: (_) =>
              const DeepLink.path('/protected', includePrefixMatches: false),
        ),
      ),
    );
    expect(router.stack.map((page) => page.name), ['HomeRoute']);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Protected'), findsNothing);
    await expectBrowserUrl('/');
  });
}
