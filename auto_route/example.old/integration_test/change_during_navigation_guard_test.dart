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

    // Steps: push Draft, whose guard asks "Leave draft?" in a dialog and lets
    // Draft in on "Yes". While the dialog is open, the user signs out and the
    // listenable notifies. The user taps "Yes".
    // Was: the dialog closed and opened again, and Draft opened only after a
    // second "Yes".
    // Should: one "Yes" opens Draft. The guard answers from the user, as an
    // alert on iOS or Android stays up through a change and is acted on once.
    // Headless test: auto_route/test/reevaluatable_router/dialog_guard_asked_once_test.dart
    testWidgets('A sign-out while the dialog of a guard is open asks the user '
        'once', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final guard = AutoRouteGuard.simple((resolver, router) async {
        final isConfirmed = await showDialog<bool>(
          context: router.root.navigatorKey.currentContext!,
          builder: (dialog) => AlertDialog(
            title: const Text('Leave draft?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        (isConfirmed ?? false) ? resolver.next() : resolver.reject();
      });
      final router = RootStackRouter.build(
        routes: [
          for (final (name, path, asked) in [
            ('HomeRoute', '/', null),
            ('DraftRoute', '/draft', guard),
          ])
            NamedRouteDef(
              name: name,
              path: path,
              guards: [?asked],
              builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
            ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);

      unawaited(router.push(const NamedRoute('DraftRoute')));
      await tester.pumpAndSettle();
      isSignedIn.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(find.text('Leave draft?'), findsNothing);
      expectTopPage(router, 'DraftRoute');
      await expectBrowserUrl('/draft');
    });
  });
}
