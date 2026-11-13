import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The pages replaceAll replaces stay until a page goes on in their place.
// The login page a guard shows takes their place as it goes on, so a
// signed-out user can't go back to the account, as Android finishes the old
// screens of a task it clears as the new one starts. A guard that shows no
// page keeps them, as Flutter's Router keeps building the current pages
// while its delegate waits.
// Headless test: auto_route/test/guards/replace_all_guard_page_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page', () {
    // Signed in, opens Home and pushes Account. Signs out and calls
    // replaceAll([HomeRoute]), whose guard sends a signed-out user to the
    // login page: with [awaitsRedirect] it awaits its redirect, and with
    // [needsSignIn] it only asks the session there, whose listener shows the
    // login page. Checks that the login page is the only page, with no back
    // button, then signs in on it and checks that Home opens alone.
    Future<void> signOutAndIn(
      WidgetTester tester, {
      bool awaitsRedirect = false,
      StreamController<StackRouter>? needsSignIn,
    }) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final signingIn = <NavigationResolver>[];
      final guard = needsSignIn != null
          ? AutoRouteGuard.simple((resolver, router) {
              if (isSignedIn.value) return resolver.next();
              signingIn.add(resolver);
              needsSignIn.add(router);
            })
          : awaitsRedirect
          ? AutoRouteGuard.simple((resolver, _) async {
              if (isSignedIn.value) return resolver.next();
              signingIn.add(resolver);
              await resolver.redirectUntil(const NamedRoute('LoginRoute'));
            })
          : AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) return resolver.next();
              signingIn.add(resolver);
              unawaited(
                resolver.redirectUntil(const NamedRoute('LoginRoute')),
              );
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
    }

    // Was: the login page went on over Home and Account, with a back button
    // that led to the account.
    testWidgets(
      'The login page a guard of replaceAll shows is the only page, '
      'and signing in opens the new page alone',
      signOutAndIn,
    );

    // The guard awaits its redirect, as the lints for futures that are not
    // awaited ask for, so its call returns only once the login page closed.
    // Was, while replaceAll waited for the guard's call to return before it
    // took the old pages off: Home and Account stayed under the login page.
    testWidgets(
      'The login page of a guard of replaceAll that awaits its redirect is '
      'the only page, and signing in opens the new page alone',
      (tester) => signOutAndIn(tester, awaitsRedirect: true),
    );

    // The guard does not put the login page on itself: it asks the session
    // for a sign-in and returns, and a listener the app added at its start
    // pushes the login page.
    // Was, while only a page the guard's own code put on took the place of
    // the old pages: Home and Account stayed under the login page.
    testWidgets(
      'The login page that a listener of the session pushes for a guard of '
      'replaceAll is the only page, and signing in opens the new page alone',
      (tester) async {
        final needsSignIn = StreamController<StackRouter>.broadcast(sync: true);
        addTearDown(needsSignIn.close);
        final listener = needsSignIn.stream.listen(
          (router) => unawaited(router.push(const NamedRoute('LoginRoute'))),
        );
        addTearDown(listener.cancel);
        await signOutAndIn(tester, needsSignIn: needsSignIn);
      },
    );

    // Steps: open Home and push Account. Call replaceAll([HelpRoute]), whose
    // guard shows no page and answers later, as one that asks in a dialog
    // does. Something above the router rebuilds the app. The guard lets Help
    // through.
    // Was: the stack was empty as the guard returned, so the rebuild showed
    // a blank screen.
    // Should: Account stays on screen until Help takes its place.
    testWidgets('The pages stay on screen through a rebuild while a guard of '
        'replaceAll that shows no page decides', (tester) async {
      final asking = <NavigationResolver>[];
      final rebuilds = ValueNotifier(0);
      addTearDown(rebuilds.dispose);
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
          page('AccountRoute', '/account'),
          page(
            'HelpRoute',
            '/help',
            AutoRouteGuard.simple((resolver, _) {
              asking.add(resolver);
            }),
          ),
        ],
      );
      final config = router.config();
      if (config.routerDelegate case final AutoRouterDelegate delegate) {
        addTearDown(delegate.dispose);
      }
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: rebuilds,
          builder: (_, version, _) =>
              MaterialApp.router(routerConfig: config, title: 'v$version'),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();

      unawaited(router.replaceAll([const NamedRoute('HelpRoute')]));
      await tester.pumpAndSettle();
      rebuilds.value++;
      await tester.pumpAndSettle();

      expectTopPage(router, 'AccountRoute');
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
      ]);
      await expectBrowserUrl('/account');

      asking.singleOrNull?.next();
      await tester.pumpAndSettle();

      expectTopPage(router, 'HelpRoute');
      expect(router.stack.map((page) => page.name), ['HelpRoute']);
      await expectBrowserUrl('/help');
    });
  });
}
