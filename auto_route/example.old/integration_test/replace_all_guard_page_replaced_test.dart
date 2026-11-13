import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The pages a guard's login page took the place of stay gone once the app
// replaces that login page with a page of its own, as a screen started with
// FLAG_ACTIVITY_CLEAR_TASK from a login screen on Android leaves no screen of
// the old task to return to.
// Headless test: auto_route/test/guards/replace_all_guard_page_replaced_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page replaced', () {
    // Steps: signed in, open Home and push Account, both behind a guard that
    // sends a signed-out user to a login page. Sign out and call
    // replaceAll([HomeRoute()]): the login page shows. On it, call
    // replaceAll([WelcomeRoute()]), as a "continue as guest" button does.
    // Was: the stack was [Home, Account, Welcome], with a back button on
    // Welcome that led to the account.
    // Should: Welcome is the only page, with no back button.
    testWidgets('replaceAll from the login page a guard of replaceAll shows '
        'leaves the new page alone', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final guard = AutoRouteGuard.simple((resolver, _) {
        if (isSignedIn.value) return resolver.next();
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
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      isSignedIn.value = false;
      unawaited(router.replaceAll([const NamedRoute('HomeRoute')]));
      await tester.pumpAndSettle();
      expectTopPage(router, 'LoginRoute');

      unawaited(router.replaceAll([const NamedRoute('WelcomeRoute')]));
      await tester.pumpAndSettle();

      expectTopPage(router, 'WelcomeRoute');
      expect(router.stack.map((page) => page.name), ['WelcomeRoute']);
      expect(router.canPop(), isFalse);
      expect(find.byType(BackButton), findsNothing);
      await expectBrowserUrl('/welcome');
    });
  });
}
