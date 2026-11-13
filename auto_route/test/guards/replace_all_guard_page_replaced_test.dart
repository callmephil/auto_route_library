import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The pages a guard's login page took the place of stay gone once the app
// replaces that login page with a page of its own. Found while proving a
// lead of the second audit of the library; on the last release too.
// Setup: Home and Account sit behind a guard that sends a signed-out user to
// a login page with redirectUntil. Welcome is open to everyone.
// Steps: signed in, open Home and push Account. Sign out and call
// replaceAll([HomeRoute()]): the login page is the only page. On it, call
// replaceAll([WelcomeRoute()]) or replace(WelcomeRoute()), as a "continue as
// guest" button does.
// Was: the stack was [Home, Account, Welcome], and back from Welcome showed
// the account to a signed-out user. The login page left, which ends the
// guard's redirect with a rejection, and a rejected replaceAll put the
// pages it had set aside back. On the last release the stack was [Home,
// Account], with Welcome gone.
// Should: [Welcome]. The new page took the place of the login page, and
// with it the place of the pages the login page had taken: they come back
// only when the login page closes with nothing in its place, as when the
// guard rejects. On Android, a screen started with FLAG_ACTIVITY_CLEAR_TASK
// from a login screen leaves no screen of the old task to return to.
//
// Only a replace of the login page itself counts. Found by the review of
// this fix (Part 6, finding 3): the login page opens "forgot password",
// which goes on to "reset" in its own place, the user goes back to the login
// page, and the guard rejects. Was, while any replaced page on the stack
// counted: no page was left. Should: [Home, Account] again, as the login
// page was never replaced.
void main() {
  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home and Account signed in, then signs out with replaceAll, which
  // shows the login page alone. With [awaitsRedirect] the guard awaits its
  // redirect. The resolvers of the guards that have not answered go to
  // [signingIn].
  Future<RootStackRouter> signOut(
    WidgetTester tester, {
    required bool awaitsRedirect,
    List<NavigationResolver>? signingIn,
  }) async {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    final guard = awaitsRedirect
        ? AutoRouteGuard.simple((resolver, _) async {
            if (isSignedIn.value) return resolver.next();
            signingIn?.add(resolver);
            await resolver.redirectUntil(const NamedRoute('LoginRoute'));
          })
        : AutoRouteGuard.simple((resolver, _) {
            if (isSignedIn.value) return resolver.next();
            signingIn?.add(resolver);
            unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
          });
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
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    isSignedIn.value = false;
    unawaited(router.replaceAll([const NamedRoute('HomeRoute')]));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['LoginRoute']);
    return router;
  }

  for (final awaitsRedirect in [false, true]) {
    final shape = awaitsRedirect ? 'awaits' : 'starts';

    testWidgets('replaceAll from the login page of a guard that $shape its '
        'redirect leaves the new page alone', (tester) async {
      final router = await signOut(tester, awaitsRedirect: awaitsRedirect);

      unawaited(router.replaceAll([const NamedRoute('WelcomeRoute')]));
      await tester.pumpAndSettle();

      expect(stackNames(router), ['WelcomeRoute']);
      expect(find.text('WelcomeRoute'), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(router.activeGuardObserver.guardInProgress, isFalse);
    });

    testWidgets('replace on the login page of a guard that $shape its '
        'redirect leaves the new page alone', (tester) async {
      final router = await signOut(tester, awaitsRedirect: awaitsRedirect);

      unawaited(router.replace(const NamedRoute('WelcomeRoute')));
      await tester.pumpAndSettle();

      expect(stackNames(router), ['WelcomeRoute']);
      expect(find.text('WelcomeRoute'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets('The pages come back when a page above the login page of a '
        'guard that $shape its redirect was replaced, and the guard then '
        'rejects', (tester) async {
      final signingIn = <NavigationResolver>[];
      final router = await signOut(
        tester,
        awaitsRedirect: awaitsRedirect,
        signingIn: signingIn,
      );
      unawaited(router.push(const NamedRoute('ForgotRoute')));
      await tester.pumpAndSettle();
      unawaited(router.replace(const NamedRoute('ResetRoute')));
      await tester.pumpAndSettle();
      final atReset = stackNames(router);
      router.pop();
      await tester.pumpAndSettle();

      signingIn.firstOrNull?.reject();
      await tester.pumpAndSettle();

      expect(atReset, ['LoginRoute', 'ResetRoute']);
      expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
      expect(find.text('AccountRoute'), findsOneWidget);
    });
  }
}
