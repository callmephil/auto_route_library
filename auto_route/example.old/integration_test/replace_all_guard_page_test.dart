import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The login page a guard of replaceAll shows takes the place of the pages to
// replace, so a signed-out user can't go back to the account, as Android
// finishes the old screens of a task it clears before the new one starts.
// Headless test: auto_route/test/guards/replace_all_guard_page_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page', () {
    // Steps: signed in, open Home and push Account. Sign out and call
    // replaceAll([HomeRoute]), whose guard sends a signed-out user to the
    // login page. Then sign in on it.
    // Was: the login page went on over Home and Account, with a back button
    // that led to the account.
    // Should: the login page is the only page, with no back button, and
    // signing in opens Home alone.
    testWidgets('The login page a guard of replaceAll shows is the only page, '
        'and signing in opens the new page alone', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final signingIn = <NavigationResolver>[];
      final guard = AutoRouteGuard.simple((resolver, _) {
        if (isSignedIn.value) return resolver.next();
        signingIn.add(resolver);
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
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');

      isSignedIn.value = false;
      unawaited(router.replaceAll([const NamedRoute('HomeRoute')]));
      await tester.pumpAndSettle();

      expectTopPage(router, 'LoginRoute');
      expect(router.stack.map((page) => page.name), ['LoginRoute']);
      expect(router.canPop(), isFalse);
      expect(find.byType(BackButton), findsNothing);
      await expectBrowserUrl('/login');

      isSignedIn.value = true;
      signingIn.singleOrNull?.next();
      await tester.pumpAndSettle();

      expectTopPage(router, 'HomeRoute');
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      await expectBrowserUrl('/');
    });
  });
}
