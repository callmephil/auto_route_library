import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
import '../router_test_utils.dart';

// A signed-out user must not get back to the account from the login page a
// guard of replaceAll shows. Found by the review of the fix that keeps the
// stack while a guard of replaceAll decides (audit finding C3): with that
// fix alone the old pages stayed under the guard's login page.
// Setup: Home and Account sit behind a guard that sends a signed-out user to
// a login page with redirectUntil.
// Steps: signed in, open Home and push Account. Sign out, and call
// replaceAll([HomeRoute]), as an app does on sign-out. The login page shows.
// Was, with the first fix: the stack was [Home, Account, Login], the login
// page showed a back button, and back showed the account.
// Should: the pages to replace stay only while a guard's own call runs. A
// guard that returns without an answer holds the navigation behind a page of
// its own, which takes their place: the login is the only page, and back
// shows no account. They come back only if the guard then rejects. Android
// finishes the old screens of a task it clears before the new one starts,
// whatever the new one does next.
void main() {
  // The session the guard reads, and the resolvers of the guards that sent
  // the user to the login page.
  ({ValueNotifier<bool> isSignedIn, List<NavigationResolver> signingIn})
  buildSession() {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    return (isSignedIn: isSignedIn, signingIn: <NavigationResolver>[]);
  }

  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(
      appBar: AppBar(leading: const AutoLeadingButton()),
      body: Text(name),
    ),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home and Account signed in, then signs out with replaceAll, which
  // shows the login page.
  Future<(RootStackRouter, List<NavigationResolver>, ValueNotifier<bool>)>
  signOut(WidgetTester tester) async {
    final session = buildSession();
    final guard = AutoRouteGuard.simple((resolver, _) {
      if (session.isSignedIn.value) return resolver.next();
      session.signingIn.add(resolver);
      unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
    });
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/', guard),
        page('AccountRoute', '/account', guard),
        page('LoginRoute', '/login'),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);

    session.isSignedIn.value = false;
    unawaited(router.replaceAll([const NamedRoute('HomeRoute')]));
    await tester.pumpAndSettle();
    expect(find.text('LoginRoute'), findsOneWidget);
    return (router, session.signingIn, session.isSignedIn);
  }

  testWidgets('The login page a guard of replaceAll shows is the only page, '
      'with no back button', (tester) async {
    final (router, _, _) = await signOut(tester);

    expect(stackNames(router), ['LoginRoute']);
    expect(router.canPop(), isFalse);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('Back from the login page a guard of replaceAll shows does not '
      'show the account', (tester) async {
    final (router, _, _) = await signOut(tester);

    await systemBack(tester);

    expect(find.text('AccountRoute'), findsNothing);
    expect(stackNames(router), isNot(contains('AccountRoute')));
  });

  testWidgets('Signing in on the login page a guard of replaceAll shows opens '
      'the new page alone', (tester) async {
    final (router, signingIn, isSignedIn) = await signOut(tester);

    isSignedIn.value = true;
    signingIn.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  // A rejected replaceAll leaves the stack as it was, also once its guard has
  // shown a page of its own.
  testWidgets('The pages come back when the guard that showed its login page '
      'rejects', (tester) async {
    final (router, signingIn, _) = await signOut(tester);

    signingIn.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(find.text('LoginRoute'), findsNothing);
  });
}
