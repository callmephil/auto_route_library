import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// replaceAll from the login page a log-out was answered with leaves the
// router working. Found by the second audit of the library (S2-1); on the
// last release too.
// Setup: Dashboard sits behind a guard that sends a logged-out user to a
// login page with redirectUntil, as the README's guard does. The router
// reevaluates when the session ends, as in an app that listens for an
// expired token. Welcome and Help are open to everyone.
// Steps: logged in, open Dashboard. The session ends: the login page shows
// over it.
// On the login page, call replaceAll([WelcomeRoute()]), as a "continue as
// guest" button does.
// Was: the router stayed stuck. activeGuardObserver.guardInProgress stayed
// true, the next time the session ended no guard was asked, so a guarded
// page opened in between stayed open, and code that awaited a push never
// resumed when replaceAll took its page off. Three waits held each other: the reevaluation that
// showed the login page holds back the report of pages that left until it
// ends, replaceAll left it to that report to answer the callers of the pages
// it took off, and the guard's redirect waited for the login page's caller
// to be answered.
// Should: the pages replaceAll takes off answer their callers in the step
// that replaces them, as Flutter's Navigator completes the future of every
// route that leaves its pages (Route.didComplete), whatever else is pending.
// The guard's redirect then ends, and the reevaluation with it.

void main() {
  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Dashboard logged in, ends the session, and leaves the login page
  // with replaceAll([WelcomeRoute()]). Returns the router, whether the user
  // is logged in, and what ends the session: the router is told when the
  // session ends, not when the user logs in.
  Future<(RootStackRouter, ValueNotifier<bool>, VoidCallback)> continueAsGuest(
    WidgetTester tester,
  ) async {
    final isLoggedIn = ValueNotifier(true);
    addTearDown(isLoggedIn.dispose);
    final sessionEnds = ValueNotifier(0);
    addTearDown(sessionEnds.dispose);
    void endSession() {
      isLoggedIn.value = false;
      sessionEnds.value++;
    }

    final router = RootStackRouter.build(
      routes: [
        page(
          'DashboardRoute',
          '/',
          AutoRouteGuard.simple((resolver, _) {
            if (isLoggedIn.value) return resolver.next();
            unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
          }),
        ),
        page('LoginRoute', '/login'),
        page('WelcomeRoute', '/welcome'),
        page('HelpRoute', '/help'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: sessionEnds);
    endSession();
    await tester.pumpAndSettle();
    expect(stackNames(router), ['DashboardRoute', 'LoginRoute']);

    unawaited(router.replaceAll([const NamedRoute('WelcomeRoute')]));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['WelcomeRoute']);
    return (router, isLoggedIn, endSession);
  }

  testWidgets('No guard is in progress once replaceAll has taken the login '
      'page of a log-out off', (tester) async {
    final (router, _, _) = await continueAsGuest(tester);

    expect(router.activeGuardObserver.guardInProgress, isFalse);
    expect(find.text('WelcomeRoute'), findsOneWidget);
  });

  // Steps: then log in and push Dashboard, and the session ends again.
  testWidgets('A session that ends later still sends the user to the login '
      'page', (tester) async {
    final (router, isLoggedIn, endSession) = await continueAsGuest(tester);
    isLoggedIn.value = true;
    unawaited(router.push(const NamedRoute('DashboardRoute')));
    await tester.pumpAndSettle();
    final loggedIn = stackNames(router);

    endSession();
    await tester.pumpAndSettle();

    expect(loggedIn, ['WelcomeRoute', 'DashboardRoute']);
    expect(stackNames(router), [
      'WelcomeRoute',
      'DashboardRoute',
      'LoginRoute',
    ]);
    expect(find.text('LoginRoute'), findsOneWidget);
  });

  // Steps: then push Help and wait for its result, and replace all pages.
  testWidgets('Code that awaits a later push resumes when replaceAll takes '
      'its page off', (tester) async {
    final (router, _, _) = await continueAsGuest(tester);
    var result = 'waiting';
    unawaited(
      router
          .push<String>(const NamedRoute('HelpRoute'))
          .then((value) => result = 'closed with ${value ?? 'null'}'),
    );
    await tester.pumpAndSettle();
    final atHelp = (stackNames(router).join(' '), result);

    unawaited(router.replaceAll([const NamedRoute('LoginRoute')]));
    await tester.pumpAndSettle();

    expect(atHelp, ('WelcomeRoute HelpRoute', 'waiting'));
    expect(
      (stackNames(router).join(' '), result),
      ('LoginRoute', 'closed with null'),
    );
  });
}
