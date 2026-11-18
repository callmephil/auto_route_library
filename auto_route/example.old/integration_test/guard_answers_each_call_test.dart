import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard asked again gets a resolver per call, and only the latest call
// decides, as Flutter's Router ignores the result of an older route
// transaction once a newer one has started. Headless test:
// auto_route/test/reevaluatable_router/guard_answers_each_call_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('guard answers each call', () {
    // Steps: the app opens Account. The user signs out, and the session
    // changes two more times: Account's guard keeps one callback per call.
    // The user signs in, and each callback answers yes.
    // Was: the second callback failed an assert.
    // Should: Account opens once, and nothing throws.
    testWidgets('Account opens once, and no callback fails', (tester) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final callbacks = <VoidCallback>[];
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'AccountRoute',
            path: '/account',
            guards: [
              AutoRouteGuard.simple((resolver, _) {
                if (isSignedIn.value) return resolver.next();
                callbacks.add(resolver.next);
              }),
            ],
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('AccountRoute'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      isSignedIn.value = false;
      for (var times = 0; times < 3; times++) {
        session.value++;
        await tester.pumpAndSettle();
      }
      expect(callbacks, hasLength(3));

      isSignedIn.value = true;
      for (final callback in callbacks) {
        callback();
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'AccountRoute');
      expect(router.stack, hasLength(2));
      expect(find.text('AccountRoute'), findsOneWidget);
      await expectBrowserUrl('/account');
    });
  });
}
