import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A push whose guard answers later from a callback holds up no later
// sign-out: the sign-out still closes a page for signed-in users, as
// Flutter's Router never lets an older transaction block a newer one.
// Headless test:
// auto_route/test/reevaluatable_router/unanswered_guard_keeps_rounds_test.dart
NamedRouteDef _page(String name, String path, [AutoRouteGuard? guard]) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

List<String> _names(StackRouter router) =>
    router.stack.map((page) => page.routeData.name).toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('unanswered push guard sign-out', () {
    // Steps: on Account, which a signed-in user may see, the app pushes
    // Settings, whose guard answers later from a callback. The user signs
    // out before it answers.
    // Was: Account stayed on screen for the signed-out user.
    // Should: Account closes and Home shows.
    testWidgets('A sign-out closes the page while a push waits', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      // Settings' guard answers later, from what the test does.
      final waiting = <NavigationResolver>[];
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple(
              (resolver, _) =>
                  session.value ? resolver.next() : resolver.reject(),
            ),
          ),
          _page(
            'SettingsRoute',
            '/settings',
            AutoRouteGuard.simple((resolver, _) => waiting.add(resolver)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();

      session.value = false;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(_names(router), ['HomeRoute']);
      await expectBrowserUrl('/');
    });
  });
}
