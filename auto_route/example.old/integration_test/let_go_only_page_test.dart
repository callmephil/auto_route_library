import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard asked again that returns without an answer never takes its
// router's only page. That is this package's own rule; in debug builds
// Flutter's Navigator reports an error for an empty page list, and
// UINavigationController's popToRootViewController keeps the root view
// controller.
// Headless test: auto_route/test/reevaluatable_router/let_go_answer_test.dart
NamedRouteDef _page(String name, String path, AutoRouteGuard guard) => .new(
  name: name,
  path: path,
  guards: [guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

List<String> _names(StackRouter router) =>
    router.stack.map((page) => page.routeData.name).toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('let-go only page', () {
    // Steps: the app opens on Account, its only page, whose guard lets a
    // signed-in user through and otherwise returns. The user signs out,
    // then signs in again.
    // Was: nothing on screen until the sign-in.
    // Should: Account stays on screen, and once after the sign-in.
    testWidgets("The root's only page stays while its guard decides", (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          _page(
            'AccountRoute',
            '/',
            AutoRouteGuard.simple((resolver, _) {
              if (session.value) resolver.next();
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);

      session.value = false;
      await tester.pumpAndSettle();
      final whileDeciding = _names(router).join(' ');
      final shownWhileDeciding = find.text('AccountRoute').evaluate().length;
      session.value = true;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect((whileDeciding, shownWhileDeciding), ('AccountRoute', 1));
      expectTopPage(router, 'AccountRoute');
      expect(_names(router), ['AccountRoute']);
    });
  });
}
