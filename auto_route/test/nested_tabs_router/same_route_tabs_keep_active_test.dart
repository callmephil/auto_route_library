import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Tabs built from a list, one tab per item, all of the same route: when the
// list changes, the tab on screen stays on screen.
// Setup: tabs [ItemRoute(id: 1), ItemRoute(id: 2)] of one route, told apart
// by their path param.
// Steps: open the second tab, Item 2. The list gains a third item, so
// AutoTabsRouter is rebuilt with [1, 2, 3].
// Was: Item 1 showed. The router kept Item 2's page but picked the active
// tab by route name, the first tab of that name.
// Should: Item 2 stays the active tab; the router finds it by its kept page.
// The tab history, which back goes through, follows the tabs the same way.
// Native behavior this holds to: UIKit, UITabBarController.viewControllers:
// "When changing the view controllers, the tab bar controller remembers the
// view controller object that was previously selected and attempts to
// reselect it." Flutter's DefaultTabController keeps its index when tabs are
// added after it (material_ui tab_controller.dart, didUpdateWidget).
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a tab added after the active one keeps the active tab',
      (tester) async {
        final ids = ValueNotifier([1, 2]);
        addTearDown(ids.dispose);
        final router = _buildRouter(kind, ids);
        await pumpRouterApp(tester, router);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        expect(router.urlState.url, '/item/2');

        ids.value = [1, 2, 3];
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(tabs.activeIndex, 1);
        expect(find.text('Item 2'), findsOneWidget);
      },
    );
  }

  testWidgets('back goes to the same-route tab visited before a list change', (
    tester,
  ) async {
    final ids = ValueNotifier([1, 2, 3]);
    addTearDown(ids.dispose);
    final router = _buildRouter(.indexedStack, ids, backThroughHistory: true);
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    tabs.setActiveIndex(2);
    await tester.pumpAndSettle();
    expect(find.text('Item 3'), findsOneWidget);

    ids.value = [1, 2, 3, 4];
    await tester.pumpAndSettle();
    expect(tabs.activeIndex, 2);
    expect(await tabs.maybePop(), isTrue);
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 1);
    expect(find.text('Item 2'), findsOneWidget);
  });
}

enum _Tabs { indexedStack, pageView, tabBar }

// Tabs of one route, one per id in [ids].
RootStackRouter _buildRouter(
  _Tabs kind,
  ValueNotifier<List<int>> ids, {
  bool backThroughHistory = false,
}) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => Scaffold(
        body: ValueListenableBuilder(
          valueListenable: ids,
          builder: (_, value, _) {
            final routes = [
              for (final id in value)
                NamedRoute<Object?>('ItemRoute', params: {'id': id}),
            ];
            return switch (kind) {
              .indexedStack => AutoTabsRouter(
                routes: routes,
                backThroughHistory: backThroughHistory,
              ),
              .pageView => AutoTabsRouter.pageView(routes: routes),
              .tabBar => AutoTabsRouter.tabBar(routes: routes),
            };
          },
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'ItemRoute',
          path: 'item/:id',
          builder: (_, data) =>
              Center(child: Text('Item ${data.params.getInt('id')}')),
        ),
      ],
    ),
  ],
);
