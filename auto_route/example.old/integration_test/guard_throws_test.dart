import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard that throws leaves the navigation undone and the router working,
// as Flutter's Navigator.maybePop pops nothing when the route's willPop
// throws, and Android's NavController.navigate leaves its back stack when it
// throws.
// Headless test: auto_route/test/guards/guard_throws_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('guard throws', () {
    // Steps: open Home, push Account, behind an async guard, and Other over
    // it. The guards are asked again while the guard's request fails, so it
    // throws. Then the session ends and the guards are asked once more.
    // Was: the failed check took Account and Other off the stack, and no
    // later check ran, so the sign-out closed nothing.
    // Should: Other stays on screen after the failed check, and the sign-out
    // closes Account with Other, so Home shows.
    testWidgets('A guard that throws while asked again keeps the pages, and '
        'a later sign-out still closes them', (tester) async {
      final doesThrow = ValueNotifier(false);
      addTearDown(doesThrow.dispose);
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'AccountRoute',
            path: '/account',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                await Future<void>.delayed(.zero);
                if (doesThrow.value) throw StateError('no network');
                if (isSignedIn.value) {
                  resolver.next();
                } else {
                  resolver.reject();
                }
              }),
            ],
            builder: (_, _) => page('AccountRoute'),
          ),
          NamedRouteDef(
            name: 'OtherRoute',
            path: '/other',
            builder: (_, _) => page('OtherRoute'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('OtherRoute')));
      await tester.pumpAndSettle();

      doesThrow.value = true;
      final errors = <Object>[];
      unawaited(router.reevaluateGuards().catchError(errors.add));
      await tester.pumpAndSettle();

      expect(errors.singleOrNull, isStateError);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
        'OtherRoute',
      ]);
      expect(find.text('OtherRoute'), findsOneWidget);
      expect(router.activeGuardObserver.guardInProgress, isFalse);

      doesThrow.value = false;
      isSignedIn.value = false;
      unawaited(router.reevaluateGuards());
      await tester.pumpAndSettle();

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
    });
  });
}
