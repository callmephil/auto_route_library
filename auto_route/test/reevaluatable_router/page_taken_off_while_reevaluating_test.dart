import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'auth_state.dart';

// A page the app takes off while a slow guard is asked again stays off, also
// when the guard then lets it stay. Found by the review of the library
// audit's fixes (Part 4, found on the way 1); on the last release too.
// Setup: Home, then Account and Bills behind a guard that awaits a session
// check before it answers, and Notes and Other behind none. The router
// reevaluates when the login state changes.
// Steps: open [Home, Account, Bills]. The login state changes, so the guards
// are asked again, and Account's guard waits for its check. Meanwhile the app
// calls replace(OtherRoute()). The check ends and the guard lets Account
// stay.
// Was: the stack was [Home, Account, Bills, Other]: Bills, which the app had
// replaced, was back under Other. With replaceAll([OtherRoute()]) it was
// [Account, Bills, Other], with removeWhere of Account [Home, Bills,
// Account], and with navigate(HomeRoute()) [Account, Home].
// Should: a reevaluation asks whether the pages on the stack may stay. A
// page the app took off meanwhile is no longer asked about, and an answer
// that comes late neither puts it back nor closes the pages above it. The
// reevaluation puts back only what it holds back itself: the page of a guard
// that returned without an answer, and one a guard's redirect replaced.
// Flutter's Navigator shows the list of pages it was given last, whatever an
// older caller still awaits, and on the web a navigation that a newer one
// replaces is canceled, not applied later.
void main() {
  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // The stack holds the pages [names], and the last of them shows.
  void expectStack(StackRouter router, List<String> names) {
    expect(stackNames(router), names);
    expect(find.text(names.lastOrNull ?? ''), findsOneWidget);
  }

  // Opens Home, Account and [third] logged in, with [guard] on Account and
  // Bills.
  Future<(RootStackRouter, AuthState)> open(
    WidgetTester tester,
    AutoRouteGuard Function(AuthState auth) guardOf, {
    String third = 'BillsRoute',
  }) async {
    final auth = AuthState()..isLoggedIn = true;
    addTearDown(auth.dispose);
    final guard = guardOf(auth);
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('AccountRoute', '/account', guard),
        page('BillsRoute', '/bills', guard),
        page('NotesRoute', '/notes'),
        page('OtherRoute', '/other'),
        page('LoginRoute', '/login'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(NamedRoute(third)));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute', 'AccountRoute', third]);
    return (router, auth);
  }

  // A guard that awaits [check] when it is asked again, then lets a logged-in
  // user through and rejects a logged-out one.
  AutoRouteGuard Function(AuthState auth) slowGuard(Future<void> check) =>
      (session) => .simple((resolver, _) async {
        if (resolver.isReevaluating) await check;
        if (session.isLoggedIn) return resolver.next();
        resolver.reject();
      });

  // What the app calls while the guard checks, the page it opened third
  // before, and the stack right after the call, which a logged-in user keeps,
  // and after the guard then rejects a logged-out one.
  final takeOffs = {
    'replace': (
      run: (RootStackRouter router) =>
          unawaited(router.replace(const NamedRoute('OtherRoute'))),
      third: 'BillsRoute',
      meanwhile: ['HomeRoute', 'AccountRoute', 'OtherRoute'],
      afterRejection: ['HomeRoute', 'OtherRoute'],
    ),
    'replaceAll': (
      run: (RootStackRouter router) =>
          unawaited(router.replaceAll(const [NamedRoute('OtherRoute')])),
      third: 'BillsRoute',
      meanwhile: ['OtherRoute'],
      afterRejection: ['OtherRoute'],
    ),
    'removeWhere of the page being asked about': (
      run: (RootStackRouter router) {
        router.removeWhere((route) => route.name == 'AccountRoute');
      },
      third: 'NotesRoute',
      meanwhile: ['HomeRoute', 'NotesRoute'],
      afterRejection: ['HomeRoute', 'NotesRoute'],
    ),
    'navigate to a page below': (
      run: (RootStackRouter router) =>
          unawaited(router.navigate(const NamedRoute('HomeRoute'))),
      third: 'BillsRoute',
      meanwhile: ['HomeRoute'],
      afterRejection: ['HomeRoute'],
    ),
  };

  for (final MapEntry(key: name, value: takeOff) in takeOffs.entries) {
    // The login state changes and stays logged in, as after a token refresh.
    testWidgets('After $name while a slow guard checks, its yes puts no page '
        'back', (tester) async {
      final check = Completer<void>();
      final (router, auth) = await open(
        tester,
        slowGuard(check.future),
        third: takeOff.third,
      );

      auth.isLoggedIn = true;
      await tester.pumpAndSettle();
      takeOff.run(router);
      await tester.pumpAndSettle();
      final meanwhile = stackNames(router);
      check.complete();
      await tester.pumpAndSettle();

      expect(meanwhile, takeOff.meanwhile);
      expectStack(router, takeOff.meanwhile);
    });

    // The user logs out: Account's guard rejects, late. A page still on the
    // stack closes; one the app took off closes nothing more.
    testWidgets('After $name while a slow guard checks, its no closes only '
        'pages still on the stack', (tester) async {
      final check = Completer<void>();
      final (router, auth) = await open(
        tester,
        slowGuard(check.future),
        third: takeOff.third,
      );

      auth.isLoggedIn = false;
      await tester.pumpAndSettle();
      takeOff.run(router);
      await tester.pumpAndSettle();
      check.complete();
      await tester.pumpAndSettle();

      expectStack(router, takeOff.afterRejection);
    });
  }

  // The guard's late answer is a login page: with no page left to show it
  // for, none opens.
  testWidgets('A slow guard that then redirects shows no login page for a '
      'page replaceAll took off', (tester) async {
    final check = Completer<void>();
    final (router, auth) = await open(
      tester,
      (session) => .simple((resolver, _) async {
        if (resolver.isReevaluating) await check.future;
        if (session.isLoggedIn) return resolver.next();
        await resolver.redirectUntil(const NamedRoute('LoginRoute'));
      }),
    );

    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    unawaited(router.replaceAll(const [NamedRoute('OtherRoute')]));
    await tester.pumpAndSettle();
    check.complete();
    await tester.pumpAndSettle();

    expectStack(router, ['OtherRoute']);
  });

  // No slow guard is needed (second audit, S2-1's neighbor): a log-out shows
  // the guard's login page over Account, and the login page logs the user in
  // and resets the stack in one handler. The guard waiting behind its
  // redirect is asked again by the log-in and answers yes, for a page that
  // replaceAll has taken off.
  testWidgets('A log-in and replaceAll in one handler, from the login page a '
      'log-out was answered with, leave the new page alone', (tester) async {
    final (router, auth) = await open(
      tester,
      (session) => .simple((resolver, _) {
        if (session.isLoggedIn) return resolver.next();
        unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
      }),
      third: 'NotesRoute',
    );
    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    final atLogin = stackNames(router);

    auth.isLoggedIn = true;
    unawaited(router.replaceAll(const [NamedRoute('OtherRoute')]));
    await tester.pumpAndSettle();

    expect(atLogin, ['HomeRoute', 'AccountRoute', 'NotesRoute', 'LoginRoute']);
    expectStack(router, ['OtherRoute']);
    expect(router.activeGuardObserver.guardInProgress, isFalse);
  });

  // A guard that returns without an answer has its page held back, with the
  // pages above it. replaceAll replaces those too.
  testWidgets('replaceAll also replaces the pages held back for a guard that '
      'has not answered', (tester) async {
    final waiting = <NavigationResolver>[];
    final (router, auth) = await open(
      tester,
      (session) => .simple((resolver, _) {
        if (session.isLoggedIn) return resolver.next();
        waiting.add(resolver);
      }),
    );

    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    unawaited(router.replaceAll(const [NamedRoute('OtherRoute')]));
    await tester.pumpAndSettle();
    waiting.firstOrNull?.next();
    await tester.pumpAndSettle();

    expectStack(router, ['OtherRoute']);
  });

  // What the reevaluation holds back itself still goes back on. These two
  // pass before the fix too.
  testWidgets('The pages held back for a guard that has not answered go back '
      'on when it lets its page stay', (tester) async {
    final waiting = <NavigationResolver>[];
    final (router, auth) = await open(
      tester,
      (session) => .simple((resolver, _) {
        if (session.isLoggedIn) return resolver.next();
        waiting.add(resolver);
      }),
      third: 'NotesRoute',
    );

    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    final held = stackNames(router);
    waiting.firstOrNull?.next();
    await tester.pumpAndSettle();

    expect(held, ['HomeRoute']);
    expectStack(router, ['HomeRoute', 'AccountRoute', 'NotesRoute']);
  });

  testWidgets('The page that the redirect of a guard replaced goes back on '
      'when the guard lets its page stay', (tester) async {
    final waiting = <NavigationResolver>[];
    final (router, auth) = await open(
      tester,
      (session) => .simple((resolver, _) {
        if (session.isLoggedIn) return resolver.next();
        waiting.add(resolver);
        unawaited(
          resolver.redirectUntil(const NamedRoute('LoginRoute'), replace: true),
        );
      }),
      third: 'NotesRoute',
    );

    auth.isLoggedIn = false;
    await tester.pumpAndSettle();
    final atLogin = stackNames(router);
    waiting.firstOrNull?.next();
    await tester.pumpAndSettle();

    expect(atLogin, ['HomeRoute', 'AccountRoute', 'LoginRoute']);
    expectStack(router, ['HomeRoute', 'AccountRoute', 'NotesRoute']);
  });
}
