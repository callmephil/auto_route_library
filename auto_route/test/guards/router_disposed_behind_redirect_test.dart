import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// A router disposed while a guard waits behind the page of its redirect,
// with the router's widgets still mounted, threw "A RootStackRouter was used
// after being disposed". A lead of the audit of auto_route/lib, seen once in
// an integration test that disposed its router in a tear-down. It fails on
// dev and was closed by 802ef837, which was written for a nested router
// that leaves with its page and had no test for the root router.
// Steps: a guard sends a signed-out user to a login page with
// redirectUntil, for a push, for a replaceAll, or as the guards are asked
// again. While the login page is open, the app disposes the router, as one
// that swaps its router does.
// Was: the disposed router's redirect ended, which rejects, and the
// resolver then took the login page off the disposed router, which
// notified its listeners.
// Should: nothing is thrown, as a Navigator that is disposed with routes
// still waiting for results completes them without notifying anyone.
void main() {
  for (final call in ['push', 'replaceAll', 'a reevaluation']) {
    testWidgets('A router disposed while a guard of $call waits behind its '
        'redirect, with its widgets mounted, throws nothing', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) =>
          .new(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => Scaffold(body: Text(name)),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) return resolver.next();
              unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
            }),
          ),
          page('LoginRoute', '/login'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routeInformationParser: router.defaultRouteParser(),
          routerDelegate: router.delegate(reevaluateListenable: isSignedIn),
        ),
      );
      await tester.pumpAndSettle();
      final failures = <NavigationFailure>[];
      if (call == 'a reevaluation') {
        unawaited(router.push(const NamedRoute('AccountRoute')));
        await tester.pumpAndSettle();
      }
      isSignedIn.value = false;
      if (call == 'push') {
        unawaited(
          router.push(
            const NamedRoute('AccountRoute'),
            onFailure: failures.add,
          ),
        );
      } else if (call == 'replaceAll') {
        unawaited(
          router.replaceAll([
            const NamedRoute('AccountRoute'),
          ], onFailure: failures.add),
        );
      }
      await tester.pumpAndSettle();
      final top = router.stack.lastOrNull?.routeData.name;

      router.dispose();
      await tester.pumpAndSettle();

      expect(top, 'LoginRoute');
      expect(tester.takeException(), isNull);
    });
  }
}
