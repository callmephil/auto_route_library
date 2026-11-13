import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Tabs of one route, one tab per list item: a path, a link or a navigation
// that names one item's tab opens that tab. Found by the second audit of the
// library (a doubt of its tabs reader, decided as a fix).
// Setup: three tabs of one route, ItemRoute with the ids 1, 2 and 3 and the
// path 'item/:id', so each tab's url is '/item/<id>'.
// Steps A: on Item 2, navigatePath to '/item/3', as a link from a
// notification does with the url of a tab. The browser's back and forward
// buttons between these tabs already opened the entry's own tab.
// Steps B: the app starts at the link '/item/3'.
// Steps C: on Item 2, the tabs router's navigate to ItemRoute with id 3.
// Was: the tab on screen, or the first tab at start, became Item 3, so two
// tabs showed Item 3 and none Item 2. The tabs router found a route's tab by
// the route alone, and tabs of one route all answered the active tab.
// Should: the third tab opens and shows Item 3. The tabs stay Item 1, 2 and
// 3. With usesPathAsKey, which gives each tab its own key, it already did.
// That is the control. A path to an item no tab has, '/item/7', still
// updates the tab on screen in place, as before.
// Native behavior this holds to: on the web a url names one page, so
// opening the url of a tab shows that tab, as the browser's back button
// already does here. UIKit's UITabBarController.selectedViewController
// selects the view controller given, also among several of one class.
void main() {
  for (final kind in _Tabs.values) {
    for (final usesPathAsKey in [false, true]) {
      group('${kind.name}${usesPathAsKey ? ', usesPathAsKey' : ''}', () {
        testWidgets('a path to another same-route tab opens that tab', (
          tester,
        ) async {
          final router = _buildRouter(kind, usesPathAsKey: usesPathAsKey);
          await pumpRouterApp(tester, router);
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
            ..setActiveIndex(1);
          await tester.pumpAndSettle();
          expect(router.urlState.url, '/item/2');

          unawaited(router.navigatePath('/item/3'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_ids(tabs), [1, 2, 3]);
          expect(tabs.activeIndex, 2);
          expect(find.text('Item 3').hitTestable(), findsOneWidget);
        });

        testWidgets('an app started at the link of the third same-route tab '
            'opens that tab', (tester) async {
          final router = _buildRouter(kind, usesPathAsKey: usesPathAsKey);
          await pumpRouterApp(tester, router, initialLink: '/item/3');
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

          expect(tester.takeException(), isNull);
          expect(_ids(tabs), [1, 2, 3]);
          expect(tabs.activeIndex, 2);
          expect(find.text('Item 3').hitTestable(), findsOneWidget);
        });

        testWidgets('navigate to another same-route tab opens that tab', (
          tester,
        ) async {
          final router = _buildRouter(kind, usesPathAsKey: usesPathAsKey);
          await pumpRouterApp(tester, router);
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
            ..setActiveIndex(1);
          await tester.pumpAndSettle();

          unawaited(
            tabs.navigate(const NamedRoute('ItemRoute', params: {'id': 3})),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_ids(tabs), [1, 2, 3]);
          expect(tabs.activeIndex, 2);
          expect(find.text('Item 3').hitTestable(), findsOneWidget);
        });
      });
    }
  }

  testWidgets('control: a path to an item no tab has updates the tab on '
      'screen in place', (tester) async {
    final router = _buildRouter(.indexedStack, usesPathAsKey: false);
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();

    unawaited(router.navigatePath('/item/7'));
    await tester.pumpAndSettle();

    expect(_ids(tabs), [1, 7, 3]);
    expect(tabs.activeIndex, 1);
    expect(find.text('Item 7').hitTestable(), findsOneWidget);
  });
}

enum _Tabs { indexedStack, pageView, tabBar, builder }

List<int> _ids(TabsRouter tabs) => [
  for (final data in tabs.stackData) data.params.getInt('id'),
];

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
