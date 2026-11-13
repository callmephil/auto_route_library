import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// replaceAll from the login page a sign-out was answered with leaves the
// router working: the pages it takes off answer their callers at once, as
// Flutter's Navigator completes the future of every route that leaves its
// pages, so the guard's redirect ends and later sign-outs ask the guards.
// Headless test: auto_route/test/reevaluatable_router/replace_all_from_redirect_page_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all from redirect page', () {
    // Steps: signed in, open Dashboard, whose guard sends a signed-out user
    // to a login page. The session ends: the login page shows over it. On
    // it, call replaceAll([WelcomeRoute()]), as a "continue as guest" button
    // does. Then sign in and push Dashboard, and the session ends again.
    // Was: Dashboard stayed open after the session ended the second time, as
    // the router still waited for the first login page and asked no guard.
    // Should: the login page shows over Dashboard.
    testWidgets('A session that ends after replaceAll from the login page of '
        'an earlier sign-out shows the login page', (tester) async {
      // The router is told when the session ends, not when the user signs
      // in, as in an app that listens for an expired token.
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final sessionEnds = ValueNotifier(0);
      addTearDown(sessionEnds.dispose);
      Future<void> endSession() {
        isSignedIn.value = false;
        sessionEnds.value++;
        return tester.pumpAndSettle();
      }

      NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) =>
          .new(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page(
            'DashboardRoute',
            '/',
            AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) return resolver.next();
              unawaited(
                resolver.redirectUntil(const NamedRoute('LoginRoute')),
              );
            }),
          ),
          page('LoginRoute', '/login'),
          page('WelcomeRoute', '/welcome'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: sessionEnds);
      await endSession();
      expectTopPage(router, 'LoginRoute');

      unawaited(router.replaceAll([const NamedRoute('WelcomeRoute')]));
      await tester.pumpAndSettle();
      expectTopPage(router, 'WelcomeRoute');
      final asGuest = router.activeGuardObserver.guardInProgress;
      await expectBrowserUrl('/welcome');

      isSignedIn.value = true;
      unawaited(router.push(const NamedRoute('DashboardRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'DashboardRoute');
      await endSession();

      expect(asGuest, isFalse);
      expectTopPage(router, 'LoginRoute');
      expect(router.stack.map((page) => page.name), [
        'WelcomeRoute',
        'DashboardRoute',
        'LoginRoute',
      ]);
      await expectBrowserUrl('/login');
    });
  });
}
