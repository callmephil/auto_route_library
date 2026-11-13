import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';

// The pages replaceAll replaces stay until a page goes on the stack in their
// place: one of its own, or before that the page a guard shows while it has
// not answered. A signed-out user must not get back to the account from the
// login page a guard of replaceAll shows, and must not see a blank screen
// while a guard decides either.
// Setup: Home and Account sit behind a guard that sends a signed-out user to
// a login page.
// Steps: signed in, open Home and push Account. Sign out, and call
// replaceAll([HomeRoute]), as an app does on sign-out. The login page shows.
// Was, when the fix for a slow guard of replaceAll (audit finding C3) kept
// the pages until every guard had answered: the stack was [Home, Account,
// Login], the login page showed a back button, and back showed the account.
// Was, when the pages then left as the guard's call returned without an
// answer: the same for a guard that awaits its redirect, whose call returns
// only once the login page has closed (the review's third look). An empty
// stack, and a blank screen after a rebuild, while the guard's login page
// waited for a guard of its own, and for good behind a guard that asks in a
// dialog (the second audit, S2-3 and the doubt about C3). And a leave
// listener in a replaced page heard covered, never replaced (W2-4).
// Should: the pages leave in the step in which the guard's page goes on. It
// makes no difference whether the guard shows it with redirectUntil, awaited
// or not, or pushes it, at once or after a wait. A guard that shows no page
// keeps them until it answers. They come back only if the guard then
// rejects. A page the app pushes while a guard decides goes on over them and
// is replaced with them.
// Android finishes the old screens of a task it clears as the new one
// starts, iOS swaps a navigation stack in one step (setViewControllers), and
// Flutter's Router keeps building the current pages while its delegate
// waits.

// The session the guard reads, and the resolvers of the guards that have
// not answered.
typedef _Session = ({
  ValueNotifier<bool> isSignedIn,
  List<NavigationResolver> signingIn,
});

void main() {
  _Session buildSession() {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    return (isSignedIn: isSignedIn, signingIn: <NavigationResolver>[]);
  }

  // A guard that starts its redirect and returns.
  AutoRouteGuard startsRedirect(_Session session, {bool replace = false}) =>
      .simple((resolver, _) {
        if (session.isSignedIn.value) return resolver.next();
        session.signingIn.add(resolver);
        unawaited(
          resolver.redirectUntil(
            const NamedRoute('LoginRoute'),
            replace: replace,
          ),
        );
      });

  // A guard that awaits its redirect, after [renewal] when given, as a guard
  // that first tries to renew the session does.
  AutoRouteGuard awaitsRedirect(
    _Session session, {
    Future<void>? renewal,
    bool replace = false,
  }) => .simple((resolver, _) async {
    if (session.isSignedIn.value) return resolver.next();
    await renewal;
    session.signingIn.add(resolver);
    await resolver.redirectUntil(
      const NamedRoute('LoginRoute'),
      replace: replace,
    );
  });

  // A guard that shows no page: it answers later, as one that asks in a
  // dialog or in the callback of a request does.
  AutoRouteGuard answersLater(_Session session) => .simple((resolver, _) {
    if (session.isSignedIn.value) return resolver.next();
    session.signingIn.add(resolver);
  });

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

  // Shows [router] under a widget that rebuilds the app when the returned
  // function is called, as a theme or a session listener above the router
  // does.
  Future<Future<void> Function()> pumpApp(
    WidgetTester tester,
    RootStackRouter router,
  ) async {
    final rebuilds = ValueNotifier(0);
    addTearDown(rebuilds.dispose);
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
    return () async {
      rebuilds.value++;
      await tester.pumpAndSettle();
    };
  }

  // Opens Home and Account signed in, with the guard [guardOf] builds on
  // both, [startsRedirect] by default, and [everyRoute] as the guard for
  // every route. Then signs out with replaceAll. [whileGuardDecides] runs
  // once replaceAll is called, for a guard that takes its time, with a
  // callback that rebuilds the app.
  Future<(RootStackRouter, List<NavigationResolver>, ValueNotifier<bool>)>
  signOut(
    WidgetTester tester, {
    AutoRouteGuard Function(_Session session)? guardOf,
    AutoRouteGuard? everyRoute,
    Future<void> Function(RootStackRouter router, Future<void> Function())?
    whileGuardDecides,
  }) async {
    final session = buildSession();
    final guard = (guardOf ?? startsRedirect)(session);
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/', guard),
        page('AccountRoute', '/account', guard),
        page('HelpRoute', '/help'),
        page('LoginRoute', '/login'),
      ],
      guards: [?everyRoute],
    );
    final rebuild = await pumpApp(tester, router);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);

    session.isSignedIn.value = false;
    unawaited(router.replaceAll([const NamedRoute('HomeRoute')]));
    await tester.pumpAndSettle();
    await whileGuardDecides?.call(router, rebuild);
    await tester.pumpAndSettle();
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

  testWidgets('The login page of a guard that awaits its redirect is the only '
      'page, and back shows no account', (tester) async {
    final (router, _, _) = await signOut(tester, guardOf: awaitsRedirect);

    expect(stackNames(router), ['LoginRoute']);
    expect(find.byType(BackButton), findsNothing);
    await systemBack(tester);
    expect(find.text('AccountRoute'), findsNothing);
  });

  // While the guard's own check runs, the pages stay. They leave as the page
  // of its redirect goes on.
  testWidgets('The pages stay while a guard tries to renew the session, and '
      'leave as it then awaits its redirect', (tester) async {
    final renewal = Completer<void>();
    final (router, _, _) = await signOut(
      tester,
      guardOf: (session) => awaitsRedirect(session, renewal: renewal.future),
      whileGuardDecides: (checking, _) async {
        expect(stackNames(checking), ['HomeRoute', 'AccountRoute']);
        renewal.complete();
      },
    );

    expect(stackNames(router), ['LoginRoute']);
  });

  testWidgets('Signing in on the login page of a guard that awaits its '
      'redirect opens the new page alone', (tester) async {
    final (router, signingIn, isSignedIn) = await signOut(
      tester,
      guardOf: awaitsRedirect,
    );

    isSignedIn.value = true;
    signingIn.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  // The login page is not on the stack yet while a guard of its own decides,
  // such as a guard for every route that waits for the stored session.
  testWidgets('The pages stay, also through a rebuild, while the login page a '
      'guard redirects to waits for a guard of its own', (tester) async {
    final loginCheck = Completer<void>();
    final (router, _, _) = await signOut(
      tester,
      everyRoute: AutoRouteGuard.simple((resolver, _) async {
        if (resolver.routeName == 'LoginRoute') await loginCheck.future;
        resolver.next();
      }),
      whileGuardDecides: (checking, rebuild) async {
        await rebuild();
        expect(stackNames(checking), ['HomeRoute', 'AccountRoute']);
        expect(find.text('AccountRoute'), findsOneWidget);
        loginCheck.complete();
      },
    );

    expect(stackNames(router), ['LoginRoute']);
    expect(find.text('LoginRoute'), findsOneWidget);
  });

  for (final isLetIn in [true, false]) {
    testWidgets('The pages stay, also through a rebuild, until a guard that '
        'shows no page ${isLetIn ? 'lets the new page in' : 'rejects'}', (
      tester,
    ) async {
      final (router, signingIn, _) = await signOut(
        tester,
        guardOf: answersLater,
        whileGuardDecides: (checking, rebuild) async {
          await rebuild();
          expect(stackNames(checking), ['HomeRoute', 'AccountRoute']);
          expect(find.text('AccountRoute'), findsOneWidget);
        },
      );

      final resolver = signingIn.singleOrNull;
      isLetIn ? resolver?.next() : resolver?.reject();
      await tester.pumpAndSettle();

      final after = isLetIn ? ['HomeRoute'] : ['HomeRoute', 'AccountRoute'];
      expect(stackNames(router), after);
      expect(find.text(after.lastOrNull ?? ''), findsOneWidget);
    });
  }

  // The guard pushes its own login page, after a wait, and answers later.
  testWidgets('The login page a guard pushes itself after a wait is the only '
      'page', (tester) async {
    final renewal = Completer<void>();
    final (router, signingIn, _) = await signOut(
      tester,
      guardOf: (session) => .simple((resolver, guarded) async {
        if (session.isSignedIn.value) return resolver.next();
        await renewal.future;
        session.signingIn.add(resolver);
        unawaited(guarded.push(const NamedRoute('LoginRoute')));
      }),
      whileGuardDecides: (checking, _) async {
        expect(stackNames(checking), ['HomeRoute', 'AccountRoute']);
        renewal.complete();
      },
    );
    final atLogin = stackNames(router);

    signingIn.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(atLogin, ['LoginRoute']);
    expect(stackNames(router), ['HomeRoute']);
  });

  // The app's own page is not the guard's: it goes on over the pages to
  // replace, and is replaced with them.
  for (final isLetIn in [true, false]) {
    testWidgets('A page the app pushes while a guard decides goes on over the '
        'pages, and ${isLetIn ? 'is replaced with them' : 'stays when the '
                  'guard rejects'}', (tester) async {
      final (router, signingIn, _) = await signOut(
        tester,
        guardOf: answersLater,
        whileGuardDecides: (checking, _) async {
          unawaited(checking.push(const NamedRoute('HelpRoute')));
          await tester.pumpAndSettle();
          expect(stackNames(checking), [
            'HomeRoute',
            'AccountRoute',
            'HelpRoute',
          ]);
        },
      );

      final resolver = signingIn.singleOrNull;
      isLetIn ? resolver?.next() : resolver?.reject();
      await tester.pumpAndSettle();

      expect(
        stackNames(router),
        isLetIn ? ['HomeRoute'] : ['HomeRoute', 'AccountRoute', 'HelpRoute'],
      );
    });
  }

  // The pages leave in the step in which the login page goes on, so that
  // step reports them.
  testWidgets('A leave listener in a page that the login page of a guard of '
      'replaceAll replaces hears replaced', (tester) async {
    final leaves = <RouteLeaveKind>[];
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        NamedRouteDef(
          name: 'EditorRoute',
          path: '/editor',
          builder: (_, _) => AutoRouteLeaveListener(
            onLeave: leaves.add,
            child: const Text('EditorRoute'),
          ),
        ),
        page(
          'AccountRoute',
          '/account',
          AutoRouteGuard.simple(
            (resolver, _) => unawaited(
              resolver.redirectUntil(const NamedRoute('LoginRoute')),
            ),
          ),
        ),
        page('LoginRoute', '/login'),
      ],
    );
    await pumpApp(tester, router);
    unawaited(router.push(const NamedRoute('EditorRoute')));
    await tester.pumpAndSettle();
    final before = List.of(leaves);

    unawaited(router.replaceAll([const NamedRoute('AccountRoute')]));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['LoginRoute']);
    expect(before, isEmpty);
    expect(leaves, [RouteLeaveKind.replaced]);
  });

  // A rejected replaceAll leaves the stack as it was, also once its guard has
  // shown a page of its own. The login page takes the place of every page
  // replaceAll replaces, also with replace: none of them is under it to be
  // replaced, so a rejection brings back them all.
  for (final (shape, guardOf) in [
    ('starts', startsRedirect),
    (
      'starts, with replace,',
      (_Session session) => startsRedirect(session, replace: true),
    ),
    ('awaits', awaitsRedirect),
    (
      'awaits, with replace,',
      (_Session session) => awaitsRedirect(session, replace: true),
    ),
  ]) {
    testWidgets('The pages come back when the guard that $shape its redirect '
        'rejects', (tester) async {
      final (router, signingIn, _) = await signOut(tester, guardOf: guardOf);

      signingIn.singleOrNull?.reject();
      await tester.pumpAndSettle();

      expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
      expect(find.text('AccountRoute'), findsOneWidget);
      expect(find.text('LoginRoute'), findsNothing);
    });
  }
}
