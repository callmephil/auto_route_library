import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A push whose guard answers from a callback, then a sign-out: the guard's
// yes from before the sign-out opens nothing, as Flutter's Router drops an
// older route transaction's result once newer route information arrived.
// Headless test:
// auto_route/test/reevaluatable_router/unanswered_guard_keeps_rounds_test.dart
NamedRouteDef _page(String name, String path, AutoRouteGuard guard) => .new(
  name: name,
  path: path,
  guards: [guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('callback guard stale yes', () {
    // Steps: the app opens Account, then pushes Pushed, whose guard answers
    // later from a callback. The user signs out, then the callback says yes.
    // Was: Pushed opened for the signed-out user.
    // Should: Pushed stays closed, and Home shows.
    testWidgets('A yes from before the sign-out opens nothing', (tester) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final asks = <NavigationResolver>[];
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          _page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple(
              (resolver, _) =>
                  session.value ? resolver.next() : resolver.reject(),
            ),
          ),
          _page(
            'PushedRoute',
            '/pushed',
            AutoRouteGuard.simple((resolver, _) => asks.add(resolver)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('PushedRoute')));
      await tester.pumpAndSettle();
      final firstAsk = asks.firstOrNull;

      session.value = false;
      await tester.pumpAndSettle();
      firstAsk?.next();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(find.text('PushedRoute'), findsNothing);
      await expectBrowserUrl('/');
    });
  });
}
