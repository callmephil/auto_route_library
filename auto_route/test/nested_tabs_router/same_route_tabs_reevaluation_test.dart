import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Tabs of one route, one tab per list item, keep their pages when the guards
// are reevaluated. Found by the second audit of the library (T2-1).
// Setup: three tabs of one route, ItemRoute with the ids 1, 2 and 3 and the
// path 'item/:id', and a reevaluateListenable, as an app with a
// sign-in state has. No route has a guard.
// Steps: open the second tab, Item 2. The listenable fires, as on a token
// refresh.
// Was: the tabs became Item 1, Item 3 and Item 3. Item 2's page and its
// state were gone, and the page view, tab bar and builder threw "Multiple
// widgets used the same GlobalKey". A reevaluation found each tab by its
// route, and tabs of one route all answered the active tab, so every tab's
// page was written there.
// Should: nothing changes. Each reevaluated route carries its tab's own
// match id and finds that tab. With usesPathAsKey, which gives each tab its
// own key, it already did. That is the control.
// Native behavior this holds to: a reevaluation asks the guards again and
// leaves alone what they let stay (README, "Using Reevaluate Listenable").
// Flutter's Navigator keeps a page whose key and type are unchanged when it
// is given its pages list again (Page.canUpdate), and UIKit's
// UITabBarController keeps its viewControllers unless the app sets them.
void main() {
  for (final kind in _Tabs.values) {
    for (final usesPathAsKey in [false, true]) {
      testWidgets('${kind.name}: a reevaluation keeps each same-route tab'
          '${usesPathAsKey ? ' (control: usesPathAsKey)' : ''}', (
        tester,
      ) async {
        final auth = ValueNotifier(0);
        addTearDown(auth.dispose);
        final router = _buildRouter(kind, usesPathAsKey: usesPathAsKey);
        await pumpRouterApp(tester, router, reevaluationNotifier: auth);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        List<int> ids() => [
          for (final data in tabs.stackData) data.params.getInt('id'),
        ];

        auth.value++;
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(ids(), [1, 2, 3]);
        expect(tabs.activeIndex, 1);
        expect(find.text('Item 2').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/item/2');

        // Every tab still opens its own item.
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();
        expect(find.text('Item 1').hitTestable(), findsOneWidget);
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        expect(find.text('Item 3').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'after the tab changes');
      });
    }
  }
}

enum _Tabs { indexedStack, pageView, tabBar, builder }

RootStackRouter _buildRouter(_Tabs kind, {required bool usesPathAsKey}) {
  const routes = [
    NamedRoute<Object?>('ItemRoute', params: {'id': 1}),
    NamedRoute<Object?>('ItemRoute', params: {'id': 2}),
    NamedRoute<Object?>('ItemRoute', params: {'id': 3}),
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
            .builder => AutoTabsRouter.builder(
              routes: routes,
              builder: (_, children, tabs) =>
                  IndexedStack(index: tabs.activeIndex, children: children),
            ),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'ItemRoute',
            path: 'item/:id',
            usesPathAsKey: usesPathAsKey,
            builder: (_, data) =>
                Center(child: Text('Item ${data.params.getInt('id')}')),
          ),
        ],
      ),
    ],
  );
}
