import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The app navigates to a page whose guard let go of it (Phil's decision 4),
// then the user signs in: one copy of the page, as navigate opens a route
// once and Flutter's Navigator refuses two pages with one key.
// Headless test: auto_route/test/reevaluatable_router/let_go_answer_test.dart
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

  group('let-go navigate one copy', () {
    // Steps: the user signs out on Account. Then the app navigates to
    // Account, and its guard waits too. After that the user signs in and goes
    // back.
    // Was: two Account pages, and back showed Account again.
    // Should: one Account, and back shows Home.
    testWidgets('One copy of the page, and back shows the page under it', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (session.value) resolver.next();
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      session.value = false;
      await tester.pumpAndSettle();
      unawaited(router.navigate(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();

      session.value = true;
      await tester.pumpAndSettle();
      final afterSignIn = _names(router);
      await systemBack(tester);

      expect(tester.takeException(), isNull);
      expect(afterSignIn, ['HomeRoute', 'AccountRoute']);
      expectTopPage(router, 'HomeRoute');
      await expectBrowserUrl('/');
    });
  });
}
