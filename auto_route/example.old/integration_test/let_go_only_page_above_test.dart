import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The pages above a router's only page leave with a let-go (Phil's decision
// 4), while the only page itself stays, as UINavigationController keeps its
// root view controller and pops the ones above it.
// Headless test: auto_route/test/reevaluatable_router/let_go_answer_test.dart
NamedRouteDef _page(String name, String path, AutoRouteGuard guard) => .new(
  name: name,
  path: path,
  guards: [guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('let-go only page above', () {
    // Steps: the app opens on Overview, whose guard lets a signed-in user
    // through and otherwise returns; Orders, pushed on it, turns a signed-out
    // user away. The user signs out, then signs in again.
    // Was: Orders stayed on screen for the signed-out user.
    // Should: Overview shows at once, and Orders comes back on the sign-in.
    testWidgets('The page above leaves and returns on the yes', (tester) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          _page(
            'OverviewRoute',
            '/',
            AutoRouteGuard.simple((resolver, _) {
              if (session.value) resolver.next();
            }),
          ),
          _page(
            'OrdersRoute',
            '/orders',
            AutoRouteGuard.simple(
              (resolver, _) =>
                  session.value ? resolver.next() : resolver.reject(),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('OrdersRoute')));
      await tester.pumpAndSettle();

      session.value = false;
      await tester.pumpAndSettle();
      expectTopPage(router, 'OverviewRoute');
      expect(find.text('OrdersRoute'), findsNothing);
      await expectBrowserUrl('/');
      session.value = true;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'OrdersRoute');
      await expectBrowserUrl('/orders');
    });
  });
}
