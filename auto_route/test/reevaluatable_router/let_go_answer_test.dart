import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The answer of a guard that let go of its page: a guard asked again by the
// router's reevaluateListenable that returned without an answer, so its page
// left the stack and the screen and comes back on a later yes (Phil's
// decision 4 of 2026-11-16, held_back_page_leaves_screen_test.dart). Found
// by the review of 442dba05 and 7c67ead5; each group names its finding.
// Setup: Home and Account, opened with push and awaited by the code that
// opened it. Account's guard lets a signed-in user through and otherwise
// returns, answering later. The session is the reevaluateListenable.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;
  bool isPremium = true;

  void set({bool? signedIn, bool? premium}) {
    isSignedIn = signedIn ?? isSignedIn;
    isPremium = premium ?? isPremium;
    notifyListeners();
  }
}

typedef _Behavior = FutureOr<void> Function(
  NavigationResolver resolver,
  StackRouter router,
);

void main() {
  late _Session session;
  // What Account's guard does when asked.
  late _Behavior accountBehavior;
  late List<NavigationResolver> accountAsks;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
    accountAsks = [];
    accountBehavior = (resolver, _) {
      accountAsks.add(resolver);
      if (session.isSignedIn) resolver.next();
    };
  });

  final accountGuard = AutoRouteGuard.simple(
    (resolver, router) => accountBehavior(resolver, router),
  );
  // Lets a premium user through; otherwise returns, answering later.
  final premiumGuard = AutoRouteGuard.simple((resolver, _) {
    if (session.isPremium) resolver.next();
  });

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  const pageNames = [
    'HomeRoute',
    'AccountRoute',
    'SettingsRoute',
    'SignInRoute',
  ];

  // The root's pages, the pages a tap reaches, the url, and what the code
  // that opened Account heard.
  String state(RootStackRouter router, List<String?> answers) {
    final shown = [
      for (final name in pageNames)
        if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
    ];
    final stack = router.stack.map((page) => page.routeData.name);
    return '${stack.join(' ')} | shown: ${shown.join(' ')} | '
        '${router.urlState.url} | caller: $answers';
  }

  // Home and Account, Account opened with push and awaited.
  Future<(RootStackRouter, List<String?>)> onAccount(
    WidgetTester tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('AccountRoute', '/account', guard: accountGuard),
        page('SettingsRoute', '/settings', guard: premiumGuard),
        page('SignInRoute', '/sign-in'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    final answers = <String?>[];
    unawaited(
      router.push<String>(const NamedRoute('AccountRoute')).then(answers.add),
    );
    await tester.pumpAndSettle();
    return (router, answers);
  }

  // Finding 1. Steps: the user signs out on Account, so its guard lets go.
  // The user signs in: the guard, asked again, reads the session and awaits
  // a request before it answers from what it read. While it awaits, the
  // user signs out again. Then the request completes.
  // Was: the guard's yes, from before the second sign-out, put Account back
  // for the signed-out user. The guard asked again for the page it let go
  // of was asked without the stale mark that a guard at its check gets.
  // Should: the yes is from before the last change, so it is dropped and
  // the guard asked again, as for a navigation (_canNavigate): Account
  // stays off. The last change wins.
  // Native behavior this holds to: Flutter's Router drops an older route
  // transaction's answer once newer route information has arrived
  // (_processParsedRouteInformation, router.dart).
  group('A yes from before the last change', () {
    testWidgets('does not bring the page back for a signed-out user', (
      tester,
    ) async {
      final (router, answers) = await onAccount(tester);
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      final request = Completer<void>();
      accountBehavior = (resolver, _) async {
        accountAsks.add(resolver);
        final wasSignedIn = session.isSignedIn;
        await request.future;
        if (wasSignedIn) resolver.next();
      };

      session.set(signedIn: true);
      await tester.pump();
      session.set(signedIn: false);
      await tester.pump();
      request.complete();
      await tester.pumpAndSettle();
      final afterStaleYes = state(router, answers);
      session.set(signedIn: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(afterStaleYes, 'HomeRoute | shown: HomeRoute | / | caller: []');
      // The page still comes back on a yes from after the last change.
      expect(
        state(router, answers),
        'HomeRoute AccountRoute | shown: AccountRoute | /account | caller: []',
      );
    });

    // Finding I of the second review: the guard asked once more after its
    // stale yes is a let-go guard too, and counts no more than one: nothing
    // on screen waits for it.
    // Was: guardInProgress read true while that ask ran its call.
    testWidgets('asks the guard again without counting it in progress', (
      tester,
    ) async {
      final (router, _) = await onAccount(tester);
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      final requests = <Completer<void>>[];
      accountBehavior = (resolver, _) async {
        accountAsks.add(resolver);
        final wasSignedIn = session.isSignedIn;
        final request = Completer<void>();
        requests.add(request);
        await request.future;
        if (wasSignedIn) resolver.next();
      };

      session.set(signedIn: true);
      await tester.pump();
      session.set(signedIn: false);
      await tester.pump();
      final asksBeforeStaleYes = accountAsks.length;
      requests.firstOrNull?.complete();
      await tester.pumpAndSettle();
      final whileAskedAgain = (
        accountAsks.length - asksBeforeStaleYes,
        router.activeGuardObserver.guardInProgress,
      );
      for (final request in requests) {
        if (!request.isCompleted) request.complete();
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(whileAskedAgain, (1, false));
      expect(router.activeGuardObserver.guardInProgress, isFalse);
    });

    // Passes before the fix too: no change after the guard was asked.
    testWidgets('brings the page back when no change came after it', (
      tester,
    ) async {
      final (router, answers) = await onAccount(tester);
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      final request = Completer<void>();
      accountBehavior = (resolver, _) async {
        accountAsks.add(resolver);
        final wasSignedIn = session.isSignedIn;
        await request.future;
        if (wasSignedIn) resolver.next();
      };

      session.set(signedIn: true);
      await tester.pump();
      request.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        state(router, answers),
        'HomeRoute AccountRoute | shown: AccountRoute | /account | caller: []',
      );
    });
  });

  // Finding 2. Steps: the user signs out on Account. Its guard returns, and
  // later, from a callback (as a guard that asks a session service does),
  // calls redirectUntil(SignInRoute()). The user closes the sign-in page
  // without signing in, or signs in.
  // Was: a cancel showed Account again, at /account, with its caller still
  // waiting. redirectUntil put the let-go page back under the sign-in page,
  // as it keeps a page it redirects from; the rejection that followed the
  // cancel left it there, since the let-go wait did not take a page off on
  // a no.
  // Should: a cancel leaves Account off and its caller hears null, as a
  // rejection closes a page for good; a sign-in shows Account once.
  // Native behavior this holds to: Flutter's Navigator shows only the pages
  // it is given; the README: a rejection closes the page for good.
  group('A guard that let go, then redirects from a callback', () {
    late Completer<void> later;

    setUp(() {
      accountBehavior = (resolver, _) {
        accountAsks.add(resolver);
        if (session.isSignedIn) return resolver.next();
        unawaited(
          later.future.then(
            (_) => resolver.redirectUntil(const NamedRoute('SignInRoute')),
          ),
        );
      };
    });

    Future<String> signInShown(
      WidgetTester tester,
      RootStackRouter router,
      List<String?> answers,
    ) async {
      // Made in the test's zone, so its callbacks run in the test's frames.
      later = Completer();
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      later.complete();
      await tester.pumpAndSettle();
      return state(router, answers);
    }

    testWidgets('leaves its page off when the user cancels the sign-in', (
      tester,
    ) async {
      final (router, answers) = await onAccount(tester);
      final whileSignIn = await signInShown(tester, router, answers);

      await router.maybePop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        whileSignIn,
        'HomeRoute AccountRoute SignInRoute | shown: SignInRoute | '
        '/sign-in | caller: []',
      );
      expect(
        state(router, answers),
        'HomeRoute | shown: HomeRoute | / | '
        'caller: [null]',
      );
    });

    // Passes before the fix too.
    testWidgets('shows its page once when the user signs in', (tester) async {
      final (router, answers) = await onAccount(tester);
      await signInShown(tester, router, answers);

      session.isSignedIn = true;
      accountAsks.lastOrNull?.next();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        state(router, answers),
        'HomeRoute AccountRoute | shown: AccountRoute | /account | caller: []',
      );
    });
  });

  // Finding 5. Steps: on Home, Account, Settings, Settings' guard lets a
  // premium user through and otherwise returns. The user signs out, no
  // longer premium: Account lets go, and Settings leaves with it. The user
  // signs in again, still not premium: Account comes back and Settings'
  // guard, asked then, returns. Then the user is premium again.
  // Was: at the sign-in Settings' caller heard null while its guard still
  // decided, and its later yes left Settings off. The wait for Account's
  // guard, once over, released every page that had left with Account,
  // Settings too, though a wait of Settings' own guard had started.
  // Should: Settings' caller waits, and Settings comes back on its yes.
  // Native behavior this holds to: Flutter's Navigator completes a route's
  // popped future only when the route leaves for good
  // (_RouteEntry.handleComplete, navigator.dart), so the code that opened a
  // page goes on waiting while the page may still come back.
  group('A page above the let-go page', () {
    testWidgets('whose guard lets go after the yes comes back on its own yes', (
      tester,
    ) async {
      final (router, answers) = await onAccount(tester);
      final settingsAnswers = <String?>[];
      unawaited(
        router
            .push<String>(const NamedRoute('SettingsRoute'))
            .then(settingsAnswers.add),
      );
      await tester.pumpAndSettle();
      session.set(signedIn: false, premium: false);
      await tester.pumpAndSettle();

      session.set(signedIn: true);
      await tester.pumpAndSettle();
      final afterSignIn = (state(router, answers), settingsAnswers.length);
      session.set(premium: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(afterSignIn, (
        'HomeRoute AccountRoute | shown: AccountRoute | /account | caller: []',
        0,
      ));
      expect(
        state(router, answers),
        'HomeRoute AccountRoute SettingsRoute | shown: SettingsRoute | '
        '/settings | caller: []',
      );
      expect(settingsAnswers, isEmpty);
    });
  });

  // Finding 3. Steps: the user signs out on Account, so its guard lets go.
  // The app calls navigate(AccountRoute()), whose guard, signed out, waits
  // too. Then the user signs in, or both asks are answered yes in turn.
  // Was: two Account pages on the stack. The let-go wait put its page back
  // on its yes without looking for a page of its route that the app had put
  // on meanwhile.
  // Should: one Account, the one the app's navigation put on: a page the
  // app opens again while its guard decides takes the let-go page's place,
  // as a page the app takes off meanwhile stays off; the let-go page's
  // caller hears null.
  // A push of the same route with other arguments (finding H of the second
  // review) opens another page: both come back.
  // Native behavior this holds to: navigate reaches a page already open
  // rather than open a second one, as Android's Navigation does with
  // launchSingleTop and popUpTo (developer.android.com/guide/navigation/
  // backstack) and UIKit's popToViewController(_:animated:); a push opens a
  // new screen on iOS (pushViewController(_:animated:)) and Android, so two
  // items are two pages.
  group('A navigation to the let-go page meanwhile', () {
    Future<(RootStackRouter, List<String?>)> navigatedTo(
      WidgetTester tester,
    ) async {
      final (router, answers) = await onAccount(tester);
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      unawaited(router.navigate(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      return (router, answers);
    }

    testWidgets('leaves one copy once the user signs in', (tester) async {
      final (router, answers) = await navigatedTo(tester);

      session.set(signedIn: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        state(router, answers),
        'HomeRoute AccountRoute | shown: AccountRoute | /account | '
        'caller: [null]',
      );
    });

    testWidgets("leaves one copy when the navigation's ask, then the let-go "
        'ask, say yes', (tester) async {
      final (router, answers) = await navigatedTo(tester);
      final letGoAsk = accountAsks.elementAtOrNull(1);

      session.isSignedIn = true;
      accountAsks.lastOrNull?.next();
      await tester.pumpAndSettle();
      letGoAsk?.next();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        state(router, answers),
        'HomeRoute AccountRoute | shown: AccountRoute | /account | '
        'caller: [null]',
      );
    });

    testWidgets("leaves one copy when the let-go ask, then the navigation's "
        'ask, say yes', (tester) async {
      final (router, answers) = await navigatedTo(tester);
      final letGoAsk = accountAsks.elementAtOrNull(1);

      session.isSignedIn = true;
      letGoAsk?.next();
      await tester.pumpAndSettle();
      accountAsks.lastOrNull?.next();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        state(router, answers),
        'HomeRoute AccountRoute | shown: AccountRoute | /account | '
        'caller: [null]',
      );
    });

    testWidgets('of the same route with other arguments brings both back', (
      tester,
    ) async {
      final itemGuard = AutoRouteGuard.simple((resolver, _) {
        if (session.isSignedIn) resolver.next();
      });
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          NamedRouteDef(
            name: 'ItemRoute',
            path: '/item/:id',
            guards: [itemGuard],
            builder: (_, data) =>
                Scaffold(body: Text('Item ${data.params.getInt('id')}')),
          ),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      final answers = <String>[];
      unawaited(
        router
            .pushPath<String>('/item/1')
            .then((result) => answers.add('1: ${result ?? 'no result'}')),
      );
      await tester.pumpAndSettle();
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      unawaited(
        router
            .pushPath<String>('/item/2')
            .then((result) => answers.add('2: ${result ?? 'no result'}')),
      );
      await tester.pumpAndSettle();

      session.set(signedIn: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        router.stack.map((page) => page.routeData.params.optInt('id')),
        unorderedEquals([null, 1, 2]),
      );
      expect(answers, isEmpty);
    });
  });

  // Finding 4, as the orchestrator decided by rule 8. Steps: the guarded
  // page is the only page of the root, or of a nested router (a shell whose
  // one child is guarded). The user signs out: the guard returns without an
  // answer. Then the user signs in again, or a later change ends as a no.
  // Was: the root's stack emptied and nothing showed until the yes; the
  // nested router emptied, opened its first route again, a second page
  // whose push waited on the same guard, and the sign-in put both on.
  // Should: a let-go never takes a router's last page. It stays on the stack
  // and on screen until the guard answers, while later changes go on as for
  // any let-go guard; a yes leaves one copy, and a no does what a no on that
  // page in a reevaluation does: the root shows no page, and the nested
  // router opens its first route again, through its guards.
  // Native behavior this holds to: Flutter's Navigator refuses an empty
  // page list (navigator.dart), UINavigationController never takes its
  // root view controller off, and an emptied Android task closes the app.
  group("A router's only page", () {
    late List<String> asked;

    setUp(() => asked = []);

    final onlyGuard = AutoRouteGuard.simple((resolver, _) {
      asked.add(resolver.routeName);
      if (session.isSignedIn) return resolver.next();
      // A later change that ends as a no.
      if (!session.isPremium) resolver.reject();
    });

    // The pages of [router] and the pages a tap reaches.
    String pagesOf(StackRouter? router) {
      final names = [...?router?.stack.map((page) => page.routeData.name)];
      final shown = [
        for (final name in {...names, 'HomeRoute'})
          if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
      ];
      return '${names.join(' ')} | shown: ${shown.join(' ')}';
    }

    for (final isLetIn in [true, false]) {
      testWidgets('stays on the root while its guard decides; then the guard '
          'says ${isLetIn ? 'yes' : 'no'}', (tester) async {
        final router = RootStackRouter.build(
          routes: [
            page('AccountRoute', '/', guard: onlyGuard),
            page('HomeRoute', '/home'),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        session.set(signedIn: false);
        await tester.pumpAndSettle();
        final seen = [pagesOf(router)];

        session.set(signedIn: isLetIn, premium: isLetIn);
        await tester.pumpAndSettle();
        seen.add(pagesOf(router));

        expect(tester.takeException(), isNull);
        expect(seen, [
          'AccountRoute | shown: AccountRoute',
          if (isLetIn) 'AccountRoute | shown: AccountRoute' else ' | shown: ',
        ]);
        expect(router.activeGuardObserver.guardInProgress, isFalse);
      });

      testWidgets('stays in a nested router while its guard decides; then '
          'the guard says ${isLetIn ? 'yes' : 'no'}', (tester) async {
        final router = RootStackRouter.build(
          routes: [
            page('HomeRoute', '/'),
            NamedRouteDef(
              name: 'ShellRoute',
              path: '/shell',
              builder: (_, _) => const AutoRouter(),
              children: [page('NestedAccountRoute', '', guard: onlyGuard)],
            ),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.pushPath('/shell'));
        await tester.pumpAndSettle();
        final shell = router.innerRouterOf<StackRouter>('ShellRoute');
        session.set(signedIn: false);
        await tester.pumpAndSettle();
        final seen = [pagesOf(shell)];
        final askedWhileHeld = asked.length;

        session.set(signedIn: isLetIn, premium: isLetIn);
        await tester.pumpAndSettle();
        seen.add(pagesOf(shell));

        expect(tester.takeException(), isNull);
        expect(seen, [
          'NestedAccountRoute | shown: NestedAccountRoute',
          if (isLetIn)
            'NestedAccountRoute | shown: NestedAccountRoute'
          else
            ' | shown: ',
        ]);
        // Asked when opened, at the sign-out, and at the later change. After
        // a no, the first route opened again is asked too, once more when
        // the reevaluation that saw the page leave opens it again after it
        // was turned down.
        expect(askedWhileHeld, 2);
        expect(asked.length, isLetIn ? 3 : greaterThanOrEqualTo(4));
      });
    }
  });

  // Finding A of the second review. Steps: the router's first page,
  // Overview, has a guard that lets a signed-in user through and otherwise
  // returns; Orders, pushed on it, has a guard that rejects a signed-out
  // user. The router is the root, or a nested router. The user signs out,
  // then signs in again, or a later change ends as Overview's no.
  // Was: the rule that keeps a router's only page kept Orders too: it stayed
  // on screen for the signed-out user, its guard never asked. After
  // Overview's later no the nested router's stack was empty while Orders
  // still showed, at /shell/orders.
  // Should: only the bottom page is kept, as UINavigationController keeps
  // its root view controller and pops the ones above it
  // (popToRootViewController(animated:)), and Orders leaves with the let-go, as
  // the pages above a let-go page do, and comes back through its own guard
  // on the yes. The screen always matches the stack.
  // Native behavior this holds to: UIKit's UINavigationController never
  // takes its root view controller off, and pops the ones above it, and
  // Flutter's Navigator needs one page (navigator.dart: "The Navigator.pages
  // must not be empty to use the Navigator.pages API").
  group("Pages above a router's only page", () {
    late List<bool> ordersAsked;

    setUp(() => ordersAsked = []);

    final overviewGuard = AutoRouteGuard.simple((resolver, _) {
      if (session.isSignedIn) return resolver.next();
      if (!session.isPremium) resolver.reject();
    });
    final ordersGuard = AutoRouteGuard.simple((resolver, _) {
      ordersAsked.add(session.isSignedIn);
      session.isSignedIn ? resolver.next() : resolver.reject();
    });

    // The pages of [router], the pages a tap reaches and the url.
    String seenIn(RootStackRouter root, StackRouter router) {
      final names = [...router.stack.map((page) => page.routeData.name)];
      final shown = [
        for (final name in ['HomeRoute', 'OverviewRoute', 'OrdersRoute'])
          if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
      ];
      return '${names.join(' ')} | shown: ${shown.join(' ')} | '
          '${root.urlState.url}';
    }

    for (final isNested in [false, true]) {
      for (final isLetIn in [true, false]) {
        final where = isNested ? 'a nested router' : 'the root';
        testWidgets('leave with the let-go in $where, then the guard says '
            '${isLetIn ? 'yes' : 'no'}', (tester) async {
          final pages = [
            page('OverviewRoute', '', guard: overviewGuard),
            page('OrdersRoute', 'orders', guard: ordersGuard),
          ];
          final router = RootStackRouter.build(
            routes: isNested
                ? [
                    page('HomeRoute', '/'),
                    NamedRouteDef(
                      name: 'ShellRoute',
                      path: '/shell',
                      builder: (_, _) => const AutoRouter(),
                      children: pages,
                    ),
                  ]
                : [
                    page('OverviewRoute', '/', guard: overviewGuard),
                    page('OrdersRoute', '/orders', guard: ordersGuard),
                  ],
          );
          await pumpRouterApp(tester, router, reevaluationNotifier: session);
          if (isNested) {
            unawaited(router.pushPath('/shell'));
            await tester.pumpAndSettle();
          }
          final target = isNested
              ? router.innerRouterOf<StackRouter>('ShellRoute')!
              : router;
          final ordersAnswers = <String?>[];
          unawaited(
            target
                .push<String>(const NamedRoute('OrdersRoute'))
                .then(ordersAnswers.add),
          );
          await tester.pumpAndSettle();
          final base = isNested ? '/shell' : '/';
          final ordersUrl = isNested ? '/shell/orders' : '/orders';

          session.set(signedIn: false);
          await tester.pumpAndSettle();
          final seen = [seenIn(router, target)];
          session.set(signedIn: isLetIn, premium: isLetIn);
          await tester.pumpAndSettle();
          seen.add(seenIn(router, target));

          expect(tester.takeException(), isNull);
          expect(seen, [
            'OverviewRoute | shown: OverviewRoute | $base',
            if (isLetIn)
              'OverviewRoute OrdersRoute | shown: OrdersRoute | $ordersUrl'
            else
              ' | shown:  | ${isNested ? '/shell' : '/'}',
          ]);
          // Asked when pushed, and on the yes; never for the signed-out user
          // while it showed.
          expect(ordersAsked, [true, if (isLetIn) true]);
          expect(ordersAnswers, isLetIn ? isEmpty : [null]);
          expect(router.activeGuardObserver.guardInProgress, isFalse);
        });
      }
    }
  });
}
