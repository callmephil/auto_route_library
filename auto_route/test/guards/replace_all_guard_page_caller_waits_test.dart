import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The code that opened a page goes on waiting for its result while
// replaceAll has set the page aside for a guard's login page. A lead of the
// review of round 4 of the library audit (Part 6, "Found on the way" 5).
// Setup: Home and Account sit behind a guard that sends a signed-out user to
// a login page with redirectUntil. Code awaits the result of
// push(AccountRoute()).
// Steps: signed in, open Home and push Account. Sign out and call
// replaceAll([HomeRoute()]): the login page is the only page. The guard
// rejects, as a cancel button does, so Home and Account are back. Account
// then closes with a result.
// Was: the awaiting code got null as the login page went on, and the result
// Account closed with later reached nobody. A second replaceAll behind a
// login page of its own ended the first one's redirect the same way, since
// a redirect waits for its login page as the code that opened it: the first
// guard rejected at once, and after both had rejected the first login page
// was left alone on the stack.
// Should: the awaiting code hears nothing while the guard decides. It gets
// the page's result if the page comes back, and null once the page is gone
// for good: as the guard lets the new pages in, or as the app replaces the
// login page. Flutter's Navigator completes a route's popped future only
// when the route leaves for good, and a page it keeps keeps its future.
void main() {
  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home and pushes Account signed in, with the answers Account's
  // caller gets in [answers], then signs out. Home's guard shows the login
  // page, Account's the page of [accountLogin]. The resolvers of the guards
  // that have not answered go to [signingIn].
  Future<RootStackRouter> signOut(
    WidgetTester tester, {
    required List<NavigationResolver> signingIn,
    List<String?>? answers,
    String accountLogin = 'LoginRoute',
  }) async {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    AutoRouteGuard guard(String login) => .simple((resolver, _) {
      if (isSignedIn.value) return resolver.next();
      signingIn.add(resolver);
      unawaited(resolver.redirectUntil(NamedRoute(login)));
    });
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/', guard('LoginRoute')),
        page('AccountRoute', '/account', guard(accountLogin)),
        page('LoginRoute', '/login'),
        page('PinRoute', '/pin'),
        page('WelcomeRoute', '/welcome'),
      ],
    );
    await pumpRouterApp(tester, router);
    unawaited(
      router
          .push<String>(const NamedRoute('AccountRoute'))
          .then((answer) => answers?.add(answer)),
    );
    await tester.pumpAndSettle();
    isSignedIn.value = false;
    return router;
  }

  testWidgets('The code that opened a page a guard of replaceAll set aside '
      'gets its result when the guard rejects and the page closes later', (
    tester,
  ) async {
    final signingIn = <NavigationResolver>[];
    final answers = <String?>[];
    final router = await signOut(
      tester,
      signingIn: signingIn,
      answers: answers,
    );
    final failures = <NavigationFailure>[];
    unawaited(
      router.replaceAll([
        const NamedRoute('HomeRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    final atLogin = (stackNames(router).join(' '), answers.length);

    signingIn.singleOrNull?.reject();
    await tester.pumpAndSettle();
    final afterReject = (stackNames(router).join(' '), answers.length);
    unawaited(router.maybePop('saved'));
    await tester.pumpAndSettle();

    expect(atLogin, ('LoginRoute', 0));
    expect(afterReject, ('HomeRoute AccountRoute', 0));
    expect(stackNames(router), ['HomeRoute']);
    expect(answers, ['saved']);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  testWidgets('The code that opened a page a guard of replaceAll set aside '
      'gets null once the guard lets the new pages in', (tester) async {
    final signingIn = <NavigationResolver>[];
    final answers = <String?>[];
    final router = await signOut(
      tester,
      signingIn: signingIn,
      answers: answers,
    );
    unawaited(router.replaceAll([const NamedRoute('HomeRoute')]));
    await tester.pumpAndSettle();
    final atLogin = (stackNames(router).join(' '), answers.length);

    signingIn.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(atLogin, ('LoginRoute', 0));
    expect(stackNames(router), ['HomeRoute']);
    expect(answers, [null]);
  });

  testWidgets('The code that opened a page a guard of replaceAll set aside '
      'gets null once the app replaces the login page', (tester) async {
    final signingIn = <NavigationResolver>[];
    final answers = <String?>[];
    final router = await signOut(
      tester,
      signingIn: signingIn,
      answers: answers,
    );
    final failures = <NavigationFailure>[];
    unawaited(
      router.replaceAll([
        const NamedRoute('HomeRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    final atLogin = (stackNames(router).join(' '), answers.length);

    unawaited(router.replace(const NamedRoute('WelcomeRoute')));
    await tester.pumpAndSettle();

    expect(atLogin, ('LoginRoute', 0));
    expect(stackNames(router), ['WelcomeRoute']);
    expect(answers, [null]);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  testWidgets('The code that opened a page a guard of replaceAll set aside '
      'gets null when the router is disposed', (tester) async {
    final signingIn = <NavigationResolver>[];
    final answers = <String?>[];
    final router = await signOut(
      tester,
      signingIn: signingIn,
      answers: answers,
    );
    final failures = <NavigationFailure>[];
    unawaited(
      router.replaceAll([
        const NamedRoute('HomeRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    final atLogin = (stackNames(router).join(' '), answers.length);

    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await tester.pumpAndSettle();

    expect(atLogin, ('LoginRoute', 0));
    expect(answers, [null]);
    // The guard's redirect ends with its login page, which rejects.
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  // The second replaceAll sets the first one's login page aside for the
  // page of its own guard, and puts it back when that guard rejects: the
  // first guard still waits on its login page, and its rejection brings the
  // first pages back.
  for (final accountLogin in ['LoginRoute', 'PinRoute']) {
    testWidgets('Of two replaceAll calls behind the pages of their guards, '
        'LoginRoute and $accountLogin, each rejection brings back the pages '
        'its call set aside', (tester) async {
      final signingIn = <NavigationResolver>[];
      final failed = <String>[];
      final router = await signOut(
        tester,
        signingIn: signingIn,
        accountLogin: accountLogin,
      );
      unawaited(
        router.replaceAll([
          const NamedRoute('HomeRoute'),
        ], onFailure: (_) => failed.add('first')),
      );
      await tester.pumpAndSettle();
      final atFirst = stackNames(router).join(' ');
      unawaited(
        router.replaceAll([
          const NamedRoute('AccountRoute'),
        ], onFailure: (_) => failed.add('second')),
      );
      await tester.pumpAndSettle();
      final atSecond = (stackNames(router).join(' '), failed.join(' '));

      signingIn.lastOrNull?.reject();
      await tester.pumpAndSettle();
      final afterSecond = (stackNames(router).join(' '), failed.join(' '));
      signingIn.firstOrNull?.reject();
      await tester.pumpAndSettle();

      expect(atFirst, 'LoginRoute');
      expect(atSecond, (accountLogin, ''));
      expect(afterSecond, ('LoginRoute', 'second'));
      expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
      expect(failed, ['second', 'first']);
      expect(find.text('AccountRoute'), findsOneWidget);
    });
  }
}
