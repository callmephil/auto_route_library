import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard asked again that returns without an answer froze its router. A
// lead of the audit of auto_route/lib (G3 of plan 3), on dev 921fce58.
// Setup: Home, Premium and Account, each opened with push. Premium's guard
// lets a premium user through and rejects the others. Account's guard is
// written `if (isSignedIn) resolver.next();` with no else, the shape the
// test "Reevaluation with false should remove the route" pins. The session
// is the router's reevaluateListenable.
// Steps: the user signs out on Account, so its guard is asked again and
// returns without an answer. Then the session changes again (premium ends),
// the app calls reevaluateGuards(), or the user opens and closes pages.
// Was: no later change asked Premium's guard, so a user who was no longer
// premium kept the page; reevaluateGuards() never completed; leave
// listeners heard nothing more on that router; and
// activeGuardObserver.guardInProgress stayed true, so a loading indicator
// the app shows from it kept spinning. Every later reevaluation waited for
// the answer of Account's guard before it asked any page, and the first one
// never ended, holding every leave report of the router until it did.
// Should: the guard that let go of its page holds nothing else up: every
// later change asks the guards of the pages on the stack, reevaluateGuards()
// completes, leave listeners hear each leave, and the guard no longer counts
// in guardInProgress, since nothing on screen waits for it. Its page still
// comes back once it says yes.
// Native behavior this holds to: Flutter's Router works on the newest route
// information and drops the work of an older transaction when newer route
// information arrives (`_currentRouterTransaction`, router.dart), so a later
// change is never blocked by an earlier one that hangs. On Android and iOS
// an activity or a view controller that waits for a sign-in callback blocks
// no other navigation.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;
  bool isPremium = true;

  void set({bool? signedIn, bool? premium}) {
    isSignedIn = signedIn ?? isSignedIn;
    isPremium = premium ?? isPremium;
    notifyListeners();
  }
}

void main() {
  late _Session session;
  late Map<String, int> asked;
  late List<String> otherHeard;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
    asked = {};
    otherHeard = [];
  });

  void count(String guard) =>
      asked.update(guard, (n) => n + 1, ifAbsent: () => 1);

  final premiumGuard = AutoRouteGuard.simple((resolver, _) {
    count('premium');
    session.isPremium ? resolver.next() : resolver.reject();
  });
  // Never answers while signed out.
  final accountGuard = AutoRouteGuard.simple((resolver, _) {
    count('account');
    if (session.isSignedIn) resolver.next();
  });

  NamedRouteDef page(
    String name,
    String path, {
    AutoRouteGuard? guard,
    bool listens = false,
  }) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(
      body: listens
          ? AutoRouteLeaveListener(
              onLeave: (kind) => otherHeard.add(kind.name),
              child: Text(name),
            )
          : Text(name),
    ),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Home, Premium, Account; then the session ends: Account's guard is asked
  // again and returns without an answer.
  Future<(RootStackRouter, List<String?>)> signOutOnAccount(
    WidgetTester tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('PremiumRoute', '/premium', guard: premiumGuard),
        page('AccountRoute', '/account', guard: accountGuard),
        page('OtherRoute', '/other', listens: true),
        page('NotesRoute', '/notes'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    final answers = <String?>[];
    unawaited(router.push(const NamedRoute('PremiumRoute')));
    await tester.pumpAndSettle();
    unawaited(
      router.push<String>(const NamedRoute('AccountRoute')).then(answers.add),
    );
    await tester.pumpAndSettle();
    session.set(signedIn: false);
    await tester.pumpAndSettle();
    expect(names(router), ['HomeRoute', 'PremiumRoute']);
    return (router, answers);
  }

  testWidgets('A later change asks the guards of the other pages while a '
      'guard that let go of its page has not answered', (tester) async {
    final (router, _) = await signOutOnAccount(tester);
    final premiumAsked = asked['premium'];

    session.set(premium: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(asked['premium'], premiumAsked! + 1);
    expect(names(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  testWidgets('A later reevaluateGuards() completes while a guard that let '
      'go of its page has not answered', (tester) async {
    final (router, _) = await signOutOnAccount(tester);

    var isDone = false;
    unawaited(router.reevaluateGuards().then((_) => isDone = true));
    await tester.pumpAndSettle();

    expect(isDone, isTrue);
  });

  testWidgets('Leave listeners hear each leave while a guard that let go of '
      'its page has not answered', (tester) async {
    final (router, _) = await signOutOnAccount(tester);

    unawaited(router.push(const NamedRoute('OtherRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('NotesRoute')));
    await tester.pumpAndSettle();
    final heardWhenCovered = List.of(otherHeard);
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(heardWhenCovered, ['covered']);
    expect(otherHeard, ['covered', 'popped']);
    expect(names(router), ['HomeRoute', 'PremiumRoute']);
  });

  // Decided in this fix: nothing on screen waits for such a guard, which may
  // wait minutes for a sign-in, so a loading indicator shown from
  // guardInProgress would cover the app meanwhile.
  testWidgets('A guard that let go of its page no longer counts as in '
      'progress', (tester) async {
    final (router, _) = await signOutOnAccount(tester);

    expect(router.activeGuardObserver.guardInProgress, isFalse);
    expect(router.activeGuardObserver.activeGuards, isEmpty);
  });

  // Passes before the fix too.
  testWidgets('Signing in again asks the guard again, its page comes back '
      'and its caller still gets the result', (tester) async {
    final (router, answers) = await signOutOnAccount(tester);

    session.set(signedIn: true);
    await tester.pumpAndSettle();
    final afterSignIn = names(router);
    var isDone = false;
    unawaited(router.reevaluateGuards().then((_) => isDone = true));
    await tester.pumpAndSettle();
    final answersBeforeClose = List.of(answers);
    unawaited(router.maybePop('saved'));
    await tester.pumpAndSettle();

    expect(afterSignIn, ['HomeRoute', 'PremiumRoute', 'AccountRoute']);
    expect(isDone, isTrue);
    expect(answersBeforeClose, isEmpty);
    expect(answers, ['saved']);
  });

  testWidgets('Signing in again after premium ended meanwhile brings back '
      'Account alone, on the page the user then sees', (tester) async {
    final (router, answers) = await signOutOnAccount(tester);
    session.set(premium: false);
    await tester.pumpAndSettle();

    session.set(signedIn: true);
    await tester.pumpAndSettle();

    expect(names(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(answers, isEmpty);
  });

  // Passes before the fix too.
  testWidgets('A router disposed while a guard that let go of its page has '
      'not answered answers the caller with null', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('AccountRoute', '/account', guard: accountGuard),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routeInformationParser: router.defaultRouteParser(),
        routerDelegate: router.delegate(reevaluateListenable: session),
      ),
    );
    await tester.pumpAndSettle();
    final answers = <String?>[];
    unawaited(
      router.push<String>(const NamedRoute('AccountRoute')).then(answers.add),
    );
    await tester.pumpAndSettle();
    session.set(signedIn: false);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(answers, [null]);
  });

  group('The active tab', () {
    late List<String> askedTabs;

    setUp(() => askedTabs = []);

    NamedRouteDef tab(String name, String path, {AutoRouteGuard? guard}) =>
        .new(
          name: name,
          path: path,
          guards: [?guard],
          builder: (_, _) => Center(child: Text(name)),
        );

    // Feed, Profile (its guard lets a signed-in user through and has no
    // else) and Plans (its guard asks whether the user is premium). Opens
    // Profile and signs out.
    Future<(RootStackRouter, TabsRouter)> signOutOnProfile(
      WidgetTester tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter(
                routes: [
                  NamedRoute('FeedTab'),
                  NamedRoute('ProfileTab'),
                  NamedRoute('PlansTab'),
                ],
              ),
            ),
            children: [
              tab('FeedTab', 'feed'),
              tab(
                'ProfileTab',
                'profile',
                guard: AutoRouteGuard.simple((resolver, _) {
                  askedTabs.add('ProfileTab');
                  if (session.isSignedIn) resolver.next();
                }),
              ),
              tab('PlansTab', 'plans', guard: premiumGuard),
            ],
          ),
          page('PremiumRoute', '/premium', guard: premiumGuard),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
        ..setActiveIndex(1);
      await tester.pumpAndSettle();
      session.set(signedIn: false);
      await tester.pumpAndSettle();
      return (router, tabs);
    }

    testWidgets('A tab whose guard let go of it holds no later change up', (
      tester,
    ) async {
      final (router, _) = await signOutOnProfile(tester);
      unawaited(router.push(const NamedRoute('PremiumRoute')));
      await tester.pumpAndSettle();
      final premiumAsked = asked['premium'];
      var isDone = false;

      unawaited(router.reevaluateGuards().then((_) => isDone = true));
      await tester.pumpAndSettle();
      session.set(premium: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(isDone, isTrue);
      expect(asked['premium'], premiumAsked! + 2);
      expect(names(router), ['HomeRoute']);
      expect(router.activeGuardObserver.guardInProgress, isFalse);
    });

    testWidgets('A tab whose guard let go of it leaves the screen, and shows '
        'again once the guard says yes', (tester) async {
      final (router, tabs) = await signOutOnProfile(tester);
      final whileHeld = (tabs.activeIndex, router.urlState.url);
      final profileShownWhileHeld = find.text('ProfileTab').evaluate().length;

      session.set(signedIn: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(whileHeld, (0, '/feed'));
      expect(profileShownWhileHeld, 0);
      expect((tabs.activeIndex, router.urlState.url), (1, '/profile'));
      expect(find.text('ProfileTab'), findsOneWidget);
    });

    testWidgets('A tab whose guard let go of it stays closed when the user '
        'chose another tab before the guard said yes', (tester) async {
      final (router, tabs) = await signOutOnProfile(tester);
      tabs.setActiveIndex(2);
      await tester.pumpAndSettle();

      session.set(signedIn: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect((tabs.activeIndex, router.urlState.url), (2, '/plans'));
    });
  });
}
