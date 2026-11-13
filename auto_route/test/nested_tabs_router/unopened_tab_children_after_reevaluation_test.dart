import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab not opened yet keeps the pages it is to open with when the guards
// are reevaluated meanwhile. Found by the second audit of the library
// (T2-2).
// Setup: the tabs FeedTab and ProfileTab, listed with the children
// ProfileInfoRoute and ProfileOrdersRoute. ProfileTab holds a nested router
// whose first page is ProfileInfoRoute. A reevaluateListenable, as an app with a sign-in
// state has. No route has a guard.
// Steps: the app shows FeedTab; ProfileTab was never opened. The listenable
// fires, as when the session is read from disk at start or a token is
// refreshed. Then open ProfileTab.
// Was: ProfileTab opened on ProfileInfoRoute alone. The reevaluation gave a
// tab whose nested router wasn't built yet empty children, and they became
// the pages it was to open with.
// Should: ProfileTab opens with Orders on top of Info, as it does without
// the reevaluation (the control). A tab restored after the app was ended
// keeps its pages the same way (test/restoration/restore_tabs_test.dart).
// Native behavior this holds to: a reevaluation asks the guards again and
// leaves alone what they let stay (README, "Using Reevaluate Listenable"),
// as the stack router already does for a page whose nested router isn't
// built. Android's bottom navigation keeps the saved back stack of a tab
// not shown (NavController, multiple back stacks), and UIKit's
// UITabBarController keeps each tab's navigation stack while another tab
// is selected.
void main() {
  for (final kind in _Tabs.values) {
    for (final reevaluates in [true, false]) {
      testWidgets('${kind.name}: a tab opened '
          '${reevaluates ? 'after a reevaluation' : 'with no reevaluation '
                    '(control)'} shows the pages listed for it', (
        tester,
      ) async {
        final auth = ValueNotifier(0);
        addTearDown(auth.dispose);
        final router = _buildRouter(kind);
        await pumpRouterApp(tester, router, reevaluationNotifier: auth);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

        if (reevaluates) {
          auth.value++;
          await tester.pumpAndSettle();
        }
        tabs.setActiveIndex(1);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          tabs
              .innerRouterOf<StackRouter>('ProfileTab')
              ?.stackData
              .map((data) => data.name)
              .toList(),
          ['ProfileInfoRoute', 'ProfileOrdersRoute'],
        );
        expect(find.text('ProfileOrdersRoute'), findsOneWidget);
      });
    }
  }

  // A tab that keeps no state opens after a reevaluation as it does without
  // one. Found by the review of this fix, whose first form gave such a tab
  // the pages it was first opened with again.
  // Setup: ProfileTab has maintainState false, so its nested router is
  // disposed when another tab shows.
  // Steps: open ProfileTab on Orders, by the listed pages or by a path. Go
  // back to its first page, leave it, and the listenable fires. Open it
  // again.
  // Was: it opened on Orders again. The reevaluation gave the tab the
  // children of its route, the pages it was first opened with, in place of
  // the pages still waiting, which are none.
  // Should: ProfileInfoRoute alone, as without the reevaluation. A tab whose
  // nested router isn't built is left as it is.
  for (final opensByPath in [false, true]) {
    testWidgets('a tab that keeps no state, opened '
        '${opensByPath ? 'by a path to its second page' : 'with its listed '
                  'pages'}, opens on its first page after a reevaluation', (
      tester,
    ) async {
      final auth = ValueNotifier(0);
      addTearDown(auth.dispose);
      final router = _buildDroppedTabRouter(hasInitialChild: true);
      await pumpRouterApp(tester, router, reevaluationNotifier: auth);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
      if (opensByPath) {
        unawaited(router.navigatePath('/profiletab/orders'));
      } else {
        tabs.setActiveIndex(1);
      }
      await tester.pumpAndSettle();
      expect(find.text('ProfileOrdersRoute'), findsOneWidget);
      unawaited(tabs.stackRouterOfIndex(1)!.maybePop());
      await tester.pumpAndSettle();
      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();

      auth.value++;
      await tester.pumpAndSettle();
      tabs.setActiveIndex(1);
      await tester.pumpAndSettle();

      expect(_profilePages(tabs), ['ProfileInfoRoute']);
      expect(router.urlState.url, '/profiletab');
    });
  }

  // The same tab with no initial child: navigate to it with no children
  // opens its listed pages, after a reevaluation as without one, since the
  // route the tab was opened with stays as it is.
  testWidgets('navigate to a tab that keeps no state and has no initial '
      'child opens its listed pages after a reevaluation', (tester) async {
    final auth = ValueNotifier(0);
    addTearDown(auth.dispose);
    final router = _buildDroppedTabRouter(hasInitialChild: false);
    await pumpRouterApp(tester, router, reevaluationNotifier: auth);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    unawaited(tabs.stackRouterOfIndex(1)!.maybePop());
    await tester.pumpAndSettle();
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();

    auth.value++;
    await tester.pumpAndSettle();
    unawaited(tabs.navigate(const NamedRoute('ProfileTab')));
    await tester.pumpAndSettle();

    expect(_profilePages(tabs), ['ProfileInfoRoute', 'ProfileOrdersRoute']);
  });
}

// The builder kind builds every tab at the start, so its tabs are never
// waiting to open.
enum _Tabs { indexedStack, pageView, tabBar }

RootStackRouter _buildRouter(_Tabs kind) {
  const routes = [
    NamedRoute<Object?>('FeedTab'),
    NamedRoute<Object?>(
      'ProfileTab',
      children: [
        NamedRoute('ProfileInfoRoute'),
        NamedRoute('ProfileOrdersRoute'),
      ],
    ),
  ];
  return .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .indexedStack => const AutoTabsRouter(routes: routes),
            .pageView => const AutoTabsRouter.pageView(routes: routes),
            .tabBar => const AutoTabsRouter.tabBar(routes: routes),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'FeedTab',
            path: 'feedtab',
            builder: (_, _) => const Center(child: Text('FeedTab')),
          ),
          NamedRouteDef(
            name: 'ProfileTab',
            path: 'profiletab',
            builder: (_, _) => const AutoRouter(),
            children: [
              NamedRouteDef(
                name: 'ProfileInfoRoute',
                path: '',
                builder: (_, _) =>
                    const Center(child: Text('ProfileInfoRoute')),
              ),
              NamedRouteDef(
                name: 'ProfileOrdersRoute',
                path: 'orders',
                builder: (_, _) =>
                    const Center(child: Text('ProfileOrdersRoute')),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

List<String> _profilePages(TabsRouter tabs) => [
  ...?tabs.stackRouterOfIndex(1)?.stackData.map((data) => data.name),
];

// FeedTab and ProfileTab, listed with Info and Orders. ProfileTab keeps no
// state while another tab shows.
RootStackRouter _buildDroppedTabRouter({required bool hasInitialChild}) =>
    .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute('FeedTab'),
                NamedRoute(
                  'ProfileTab',
                  children: [
                    NamedRoute('ProfileInfoRoute'),
                    NamedRoute('ProfileOrdersRoute'),
                  ],
                ),
              ],
            ),
          ),
          children: [
            NamedRouteDef(
              name: 'FeedTab',
              path: 'feedtab',
              builder: (_, _) => const Center(child: Text('FeedTab')),
            ),
            NamedRouteDef(
              name: 'ProfileTab',
              path: 'profiletab',
              maintainState: false,
              builder: (_, _) => const AutoRouter(),
              children: [
                NamedRouteDef(
                  name: 'ProfileInfoRoute',
                  path: hasInitialChild ? '' : 'info',
                  builder: (_, _) =>
                      const Center(child: Text('ProfileInfoRoute')),
                ),
                NamedRouteDef(
                  name: 'ProfileOrdersRoute',
                  path: 'orders',
                  builder: (_, _) =>
                      const Center(child: Text('ProfileOrdersRoute')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
