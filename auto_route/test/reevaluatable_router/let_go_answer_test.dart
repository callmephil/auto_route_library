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
  // Native behavior this holds to: navigate opens a route once, as
  // Flutter's Navigator refuses two pages with one key.
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
  });
}
