import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The code that opened a page goes on waiting for its result while
// replaceAll has set the page aside for a guard's login page: it gets the
// result if the page comes back and closes later, as Flutter's Navigator
// completes a route's popped future only when the route leaves for good.
// Headless test: auto_route/test/guards/replace_all_guard_page_caller_waits_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page caller waits', () {
    // Steps: signed in, open Home and push Account, both behind a guard that
    // sends a signed-out user to a login page. Home shows what Account
    // closed with. Sign out and call replaceAll([HomeRoute()]): the login
    // page shows. The guard rejects, as a cancel button does, and Account is
    // back. Account closes with "saved".
    // Was: Home showed "Account closed with nothing". The code that opened
    // Account got null as the login page went on, and "saved" reached
    // nobody.
    // Should: Home shows "Account closed with saved".
    testWidgets('A page that comes back when a guard of replaceAll rejects '
        'still answers the code that opened it', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final answer = ValueNotifier('Account is open');
      addTearDown(answer.dispose);
      final signingIn = <NavigationResolver>[];
      final failures = <NavigationFailure>[];
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
              body: SafeArea(
                child: Column(
                  children: [
                    Text(name),
                    ValueListenableBuilder(
                      valueListenable: answer,
                      builder: (_, shown, _) => Text('$name: $shown'),
                    ),
                  ],
                ),
              ),
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
      unawaited(
        router
            .push<String>(const NamedRoute('AccountRoute'))
            .then(
              (result) =>
                  answer.value = 'Account closed with ${result ?? 'nothing'}',
            ),
      );
      await tester.pumpAndSettle();
      isSignedIn.value = false;
      unawaited(
        router.replaceAll([
          const NamedRoute('HomeRoute'),
        ], onFailure: failures.add),
      );
      await tester.pumpAndSettle();
      expectTopPage(router, 'LoginRoute');
      expect(find.text('LoginRoute: Account is open'), findsOneWidget);

      signingIn.singleOrNull?.reject();
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');
      expect(find.text('AccountRoute: Account is open'), findsOneWidget);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      isSignedIn.value = true;
      unawaited(router.maybePop('saved'));
      await tester.pumpAndSettle();

      expectTopPage(router, 'HomeRoute');
      expect(find.text('HomeRoute: Account closed with saved'), findsOneWidget);
      await expectBrowserUrl('/');
    });
  });
}
