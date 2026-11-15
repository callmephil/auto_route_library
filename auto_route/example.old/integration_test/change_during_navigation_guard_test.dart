import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard asked for a navigation is asked once more before its page goes in
// when the session ended while it waited: the last change wins, as Flutter's
// Router drops the answer of an older route parse when newer route
// information arrives.
// Headless test: auto_route/test/reevaluatable_router/change_during_navigation_guard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('change during navigation guard', () {
    // Steps: signed in on Home, push Account, whose guard reads the session
    // and then waits for a request. While it waits, the session ends and the
    // router's reevaluateListenable notifies. The request comes back.
    // Was: Account opened for the signed-out user and stayed until the next
    // change of the session.
    // Should: Home stays, and the push reports the guard's rejection.
    testWidgets('A sign-out while the guard of a push waits never opens the '
        'guarded page', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final request = Completer<void>();
      final guard = AutoRouteGuard.simple((resolver, _) async {
        final wasSignedIn = isSignedIn.value;
        if (!request.isCompleted) await request.future;
        wasSignedIn ? resolver.next() : resolver.reject();
      });
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('AccountRoute', '/account', guard),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final failures = <NavigationFailure>[];

      unawaited(
        router.push(const NamedRoute('AccountRoute'), onFailure: failures.add),
      );
      await tester.pump();
      isSignedIn.value = false;
      await tester.pump();
      request.complete();
      await tester.pumpAndSettle();

      expectTopPage(router, 'HomeRoute');
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('AccountRoute'), findsNothing);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      await expectBrowserUrl('/');
    });
  });
}
