import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A sign-out closes a guarded page at once while the guard of a push awaits
// a request inside its call, as Flutter's Router never holds a newer route
// transaction for an older one. Headless test:
// auto_route/test/reevaluatable_router/sign_out_while_push_guard_awaits_test.dart
NamedRouteDef _page(String name, String path, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('sign-out while push guard awaits', () {
    // Steps: the app opens Secret, then pushes Offer, whose guard awaits a
    // request. The user signs out. Then the request completes.
    // Was: Secret stayed on the screen until the request completed.
    // Should: Secret closes at once, and Offer, asked again after the
    // request, stays closed for the signed-out user.
    testWidgets('Secret closes before the request completes', (tester) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final request = Completer<void>();
      var offerAsks = 0;
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'SecretRoute',
            '/secret',
            guard: AutoRouteGuard.simple(
              (resolver, _) =>
                  session.value ? resolver.next() : resolver.reject(),
            ),
          ),
          _page(
            'OfferRoute',
            '/offer',
            guard: AutoRouteGuard.simple((resolver, _) async {
              offerAsks++;
              final isSignedIn = session.value;
              if (offerAsks == 1) await request.future;
              isSignedIn ? resolver.next() : resolver.reject();
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('SecretRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('OfferRoute')));
      await tester.pumpAndSettle();

      session.value = false;
      await tester.pumpAndSettle();
      expectTopPage(router, 'HomeRoute');
      expect(find.text('SecretRoute'), findsNothing);
      await expectBrowserUrl('/');
      request.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(find.text('OfferRoute'), findsNothing);
      await expectBrowserUrl('/');
    });
  });
}
