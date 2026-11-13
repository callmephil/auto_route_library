import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// When the guards are reevaluated, as after a sign-out, the guards of the
// active tab are asked again, and a tab they keep out leaves the screen.
// Setup: tabs [FeedTab, ProfileTab]; ProfileTab's guard lets in a signed-in
// user only. The router is given the sign-in state as its
// reevaluateListenable.
// Steps: signed in, open ProfileTab. Sign out: the listenable notifies.
// Was: ProfileTab stayed on screen and its guard was not asked:
// TabsRouter._navigateAll put each tab's page back on reevaluation and went
// on into its nested router, but asked no tab's guards.
// Should: the guard is asked again and, as it rejects, the first tab shows.
// While the guard lets the tab in, it stays.
// What this holds to: the README, "Using a Reevaluate Listenable": the
// listenable is there "to make sure private pages are only accessed by
// logged-in users all the time", and the guards are "re-called on all
// guards". The control shows the same guard on a stack page asked again, and
// its page leaving.
void main() {
  setUp(() {
    _isSignedIn = true;
    _guardCalls = 0;
  });

  testWidgets('a sign-out asks the guard of the open tab again', (
    tester,
  ) async {
    final auth = _Auth();
    addTearDown(auth.dispose);
    final router = _buildRouter();
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    expect(find.text('ProfileTab'), findsOneWidget);
    expect(_guardCalls, 1);

    auth.signOut();
    await tester.pumpAndSettle();

    expect(_guardCalls, 2);
    expect(find.text('ProfileTab'), findsNothing);
    expect(tabs.activeIndex, 0);
    expect(find.text('FeedTab'), findsOneWidget);
    expect(router.urlState.url, '/feed');
  });

  testWidgets('a reevaluation the guard passes keeps the open tab', (
    tester,
  ) async {
    final auth = _Auth();
    addTearDown(auth.dispose);
    final router = _buildRouter();
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();

    auth.stayIn();
    await tester.pumpAndSettle();

    expect(_guardCalls, 2);
    expect(tabs.activeIndex, 1);
    expect(find.text('ProfileTab'), findsOneWidget);
    expect(router.urlState.url, '/profile');
  });

  testWidgets(
    'control: a sign-out asks the guard of an open stack page again',
    (tester) async {
      final auth = _Auth();
      addTearDown(auth.dispose);
      final router = _buildRouter();
      await pumpRouterApp(tester, router, reevaluationNotifier: auth);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      expect(find.text('AccountRoute'), findsOneWidget);
      expect(_guardCalls, 1);

      auth.signOut();
      await tester.pumpAndSettle();

      expect(_guardCalls, 2);
      expect(find.text('AccountRoute'), findsNothing);
    },
  );

  // A tabs page under other pages is asked as a stack asks its pages. The
  // guards above it are asked once the guard of its active tab, and those of
  // the pages inside that tab, have answered. Found when this fix met the
  // reevaluation of covered nested routers.
  // Steps: the tabs page shows FirstTab, with OtherShellRoute and then
  // DetailsRoute over it. Two guards send a signed-out user to LoginRoute.
  // The guard "first" sits on FirstTab or on a page inside it, and "second"
  // on AccountRoute in OtherShellRoute. Sign out, then sign in.
  // Was: both guards were asked at once and two login pages opened, since
  // the tabs router answered before its guards had.
  // Should: one login page, and "second" is asked once "first" lets its page
  // stay. On iOS and Android a sign-out shows one sign-in screen.
  for (final isOnTab in [true, false]) {
    final where = isOnTab ? 'on the tab' : 'on a page inside the tab';
    testWidgets('a sign-out that a guard $where and a guard above answer with '
        'a login page shows one login page', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final asked = <String>[];
      final router = _buildCoveredTabsRouter(
        isOnTab: isOnTab,
        isSignedIn: isSignedIn,
        asked: asked,
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
        ..setActiveIndex(1);
      await tester.pumpAndSettle();
      if (!isOnTab) {
        unawaited(
          tabs
              .innerRouterOf<StackRouter>('FirstTab')!
              .push(const NamedRoute('AccountRoute')),
        );
        await tester.pumpAndSettle();
      }
      unawaited(
        router.push(
          const NamedRoute(
            'OtherShellRoute',
            children: [NamedRoute('ListRoute'), NamedRoute('AccountRoute')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();
      asked.clear();

      isSignedIn.value = false;
      await tester.pumpAndSettle();

      expect(asked, ['first']);
      expect(
        router.stack.where((page) => page.name == 'LoginRoute'),
        hasLength(1),
      );

      isSignedIn.value = true;
      await tester.pumpAndSettle();

      expect(asked, ['first', 'first', 'second']);
      expect(tabs.activeIndex, 1);
      expect(router.stack.map((page) => page.name), [
        'TabsRoute',
        'OtherShellRoute',
        'DetailsRoute',
      ]);
    });
  }
}

// Tabs [ZeroTab, FirstTab] under OtherShellRoute and DetailsRoute. The guard
// "first" is on FirstTab when [isOnTab], else on AccountRoute inside it.
RootStackRouter _buildCoveredTabsRouter({
  required bool isOnTab,
  required ValueNotifier<bool> isSignedIn,
  required List<String> asked,
}) {
  NamedRouteDef plain(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => Scaffold(body: Center(child: Text(name))),
  );
  AutoRouteGuard loginGuard(String name) => .simple((resolver, _) {
    asked.add(name);
    if (isSignedIn.value) return resolver.next();
    unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
  });
  final first = loginGuard('first');

  return .build(
    routes: [
      NamedRouteDef(
        name: 'TabsRoute',
        path: '/',
        builder: (_, _) => const AutoTabsRouter(),
        children: [
          plain('ZeroTab', 'zero'),
          if (isOnTab)
            plain('FirstTab', 'first', guards: [first])
          else
            NamedRouteDef.shell(
              name: 'FirstTab',
              path: 'first',
              children: [
                plain('ListRoute', ''),
                plain('AccountRoute', 'account', guards: [first]),
              ],
            ),
        ],
      ),
      NamedRouteDef.shell(
        name: 'OtherShellRoute',
        path: '/other',
        children: [
          plain('ListRoute', ''),
          plain('AccountRoute', 'account', guards: [loginGuard('second')]),
        ],
      ),
      plain('DetailsRoute', '/details'),
      plain('LoginRoute', '/login'),
    ],
  );
}

var _isSignedIn = true;
var _guardCalls = 0;

class _Auth extends ChangeNotifier {
  // Tells the router the sign-in state may have changed, while it hasn't.
  void stayIn() => notifyListeners();

  void signOut() {
    _isSignedIn = false;
    notifyListeners();
  }
}

final _signedInGuard = AutoRouteGuard.simple((resolver, _) {
  _guardCalls++;
  if (_isSignedIn) {
    resolver.next();
  } else {
    resolver.reject();
  }
});

RootStackRouter _buildRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute('FeedTab'), NamedRoute('ProfileTab')],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'FeedTab',
          path: 'feed',
          builder: (_, _) => const Center(child: Text('FeedTab')),
        ),
        NamedRouteDef(
          name: 'ProfileTab',
          path: 'profile',
          guards: [_signedInGuard],
          builder: (_, _) => const Center(child: Text('ProfileTab')),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'AccountRoute',
      path: '/account',
      guards: [_signedInGuard],
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('AccountRoute'))),
    ),
  ],
);
