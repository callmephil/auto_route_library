import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The pages a guard's login page took the place of stay gone once the app
// replaces that login page with a page of its own, as a screen started with
// FLAG_ACTIVITY_CLEAR_TASK from a login screen on Android leaves no screen of
// the old task to return to. Only a replace of the login page itself counts:
// a page replaced above it leaves them to come back when the guard rejects,
// as Flutter's Navigator.pushReplacement removes only the route it replaces.
// Headless test: auto_route/test/guards/replace_all_guard_page_replaced_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page replaced', () {
    // Signed in, opens Home and pushes Account, both behind a guard that
    // sends a signed-out user to a login page. Signs out and calls
    // replaceAll([HomeRoute()]): the login page shows. The resolvers of the
    // guards that have not answered go to [signingIn], and what that
    // replaceAll reports to [failures].
    Future<RootStackRouter> signOut(
      WidgetTester tester, {
      required List<NavigationFailure> failures,
      List<NavigationResolver>? signingIn,
    }) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final guard = AutoRouteGuard.simple((resolver, _) {
        if (isSignedIn.value) return resolver.next();
        signingIn?.add(resolver);
        unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
      });
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(
              appBar: AppBar(leading: const AutoLeadingButton()),
              body: SafeArea(child: Text(name)),
            ),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/', guard),
          page('AccountRoute', '/account', guard),
          page('LoginRoute', '/login'),
          page('WelcomeRoute', '/welcome'),
          page('ForgotRoute', '/forgot'),
          page('ResetRoute', '/reset'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      isSignedIn.value = false;
      unawaited(
        router.replaceAll([
          const NamedRoute('HomeRoute'),
        ], onFailure: failures.add),
      );
      await tester.pumpAndSettle();
      expectTopPage(router, 'LoginRoute');
      return router;
    }

    // Steps: sign out as above. On the login page, call
    // replaceAll([WelcomeRoute()]), as a "continue as guest" button does.
    // Was: the stack was [Home, Account, Welcome], with a back button on
    // Welcome that led to the account.
    // Should: Welcome is the only page, with no back button.
    testWidgets('replaceAll from the login page a guard of replaceAll shows '
        'leaves the new page alone', (tester) async {
      final failures = <NavigationFailure>[];
      final router = await signOut(tester, failures: failures);

      unawaited(router.replaceAll([const NamedRoute('WelcomeRoute')]));
      await tester.pumpAndSettle();

      expectTopPage(router, 'WelcomeRoute');
      expect(router.stack.map((page) => page.name), ['WelcomeRoute']);
      expect(router.canPop(), isFalse);
      expect(find.byType(BackButton), findsNothing);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      await expectBrowserUrl('/welcome');
    });

    // Steps: sign out as above. The login page opens the "forgot password"
    // page, which goes on to the "reset" page in its own place with replace.
    // Go back to the login page. The guard rejects, as a "cancel" button on
    // the login page does.
    // Was, while any replaced page counted as the login page replaced: no
    // page was left, a blank screen.
    // Should: Home and Account are back, with Account on screen.
    testWidgets('The pages come back when a page above the login page of a '
        'guard was replaced, and the guard then rejects', (tester) async {
      final signingIn = <NavigationResolver>[];
      final failures = <NavigationFailure>[];
      final router = await signOut(
        tester,
        failures: failures,
        signingIn: signingIn,
      );
      unawaited(router.push(const NamedRoute('ForgotRoute')));
      await tester.pumpAndSettle();
      unawaited(router.replace(const NamedRoute('ResetRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'ResetRoute');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expectTopPage(router, 'LoginRoute');

      signingIn.firstOrNull?.reject();
      await tester.pumpAndSettle();

      expectTopPage(router, 'AccountRoute');
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
      ]);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      await expectBrowserUrl('/account');
    });
  });
}
