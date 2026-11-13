import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'auth_state.dart';

// Signing in closes the login page of a guard that awaits its redirect, as
// it closes the one of a guard that starts its redirect and returns. Found
// while correcting replaceAll for the same shape of guard (the review's
// third look at the fixes of the library audit), and by the second audit
// (S2-2).
// Setup: Account sits behind a guard that sends a logged-out user to a login
// page with `await resolver.redirectUntil(...)`, as the lints for futures
// that are not awaited ask for. The router's reevaluateListenable is the
// login state, and the login page only logs the user in: it holds no
// resolver to call.
// Was: the login page stayed open after the login. The guard's call returns
// only once the login page has closed, and a reevaluation waited for that
// call to return before it asked the guard again.
// Should: the guard's check is over once it starts its redirect, so the
// login state's change asks it again, and its answer closes the login page.
// The state decides what shows, as SwiftUI dismisses a cover presented with
// fullScreenCover(isPresented:) once its binding turns false, and as
// Flutter's Router builds again whenever its delegate notifies.
void main() {
  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  // The router, and the route of each call of its guard.
  (RootStackRouter, List<String>) buildRouter(AuthState auth) {
    final asked = <String>[];
    final guard = AutoRouteGuard.simple((resolver, _) async {
      asked.add(resolver.routeName);
      if (auth.isLoggedIn) return resolver.next();
      await resolver.redirectUntil(const NamedRoute('LoginRoute'));
    });
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('AccountRoute', '/account', guard),
        page('LoginRoute', '/login'),
      ],
    );
    return (router, asked);
  }

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Steps: logged out, push Account, which shows the login page. Log in.
  testWidgets('Logging in closes the login page a push was sent to by a guard '
      'that awaits its redirect', (tester) async {
    final auth = AuthState();
    addTearDown(auth.dispose);
    final (router, asked) = buildRouter(auth);
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    var result = 'waiting';
    unawaited(
      router
          .push<String>(const NamedRoute('AccountRoute'))
          .then((value) => result = 'closed with ${value ?? 'null'}'),
    );
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute', 'LoginRoute']);

    auth.isLoggedIn = true;
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(asked, ['AccountRoute', 'AccountRoute']);
    // The code that pushed Account waits for the result Account closes with.
    router.pop('saved');
    await tester.pumpAndSettle();
    expect(result, 'closed with saved');
  });

  // Steps: logged in, push Account. Log out, which shows the login page over
  // it. Log in again.
  testWidgets('Logging in closes the login page a sign-out was answered with '
      'by a guard that awaits its redirect', (tester) async {
    final auth = AuthState()..isLoggedIn = true;
    addTearDown(auth.dispose);
    final (router, _) = buildRouter(auth);
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();

    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    final atLogin = stackNames(router);

    auth.isLoggedIn = true;
    await tester.pumpAndSettle();

    expect(atLogin, ['HomeRoute', 'AccountRoute', 'LoginRoute']);
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
  });

  // Steps: as above, but the login page logs the user in and closes itself
  // in one handler. Was: the guard's redirect, which ended with the pop
  // before the guard was asked again, rejected, so Account closed although
  // the user was logged in again.
  testWidgets('Account stays when the login page a sign-out was answered '
      'with logs the user in and closes itself', (tester) async {
    final auth = AuthState()..isLoggedIn = true;
    addTearDown(auth.dispose);
    final (router, _) = buildRouter(auth);
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    final atLogin = stackNames(router);

    auth.isLoggedIn = true;
    router.pop();
    await tester.pumpAndSettle();

    expect(atLogin, ['HomeRoute', 'AccountRoute', 'LoginRoute']);
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
  });

  // A change that leaves the user logged out asks the guard again, which
  // redirects again: the login page that is open stays, alone. Back from it
  // then gives up the push.
  testWidgets('A change that leaves the user logged out keeps the one login '
      'page of a guard that awaits its redirect', (tester) async {
    final auth = AuthState();
    addTearDown(auth.dispose);
    final (router, _) = buildRouter(auth);
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();

    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    final afterChange = stackNames(router);
    router.pop();
    await tester.pumpAndSettle();

    expect(afterChange, ['HomeRoute', 'LoginRoute']);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });
}
