import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The error a held page's guard throws when asked again reaches the app's
// awaited reevaluateGuards(), as the error of a guard of a page on the
// stack does, and not the zone. No native source applies to an error
// report. Headless test:
// auto_route/test/reevaluatable_router/held_page_guard_error_test.dart
NamedRouteDef _page(String name, String path, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('held page guard error', () {
    // Steps: the app opens Account. The user signs out, so Account's guard
    // returns without an answer and Account leaves the screen. The token
    // store closes, and the app awaits reevaluateGuards(). Then it opens
    // Details.
    // Was: the error reached the zone; the app's catch got nothing.
    // Should: the app's catch gets the StateError, and Details opens.
    testWidgets("The app catches a held page guard's error", (tester) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final isStoreClosed = ValueNotifier(false);
      addTearDown(isStoreClosed.dispose);
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            guard: AutoRouteGuard.simple((resolver, _) {
              if (isStoreClosed.value) {
                throw StateError('token store closed');
              }
              if (session.value) resolver.next();
            }),
          ),
          _page('DetailsRoute', '/details'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      session.value = false;
      await tester.pumpAndSettle();

      isStoreClosed.value = true;
      await expectLater(router.reevaluateGuards(), throwsStateError);
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'DetailsRoute');
      expect(find.text('DetailsRoute'), findsOneWidget);
      await expectBrowserUrl('/details');
    });
  });
}
