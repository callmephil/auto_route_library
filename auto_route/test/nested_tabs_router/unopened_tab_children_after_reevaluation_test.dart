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
