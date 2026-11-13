import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// TabsRouter.previousIndex names the tab shown before the active one, also
// after the tabs list changes.
// Setup: AutoTabsRouter built from a list of tabs that the app changes.
// Steps: show TabA, then TabB, so previousIndex names TabA. Rebuild the
// tabs with XTab in front: [XTab, TabA, TabB].
// Was: previousIndex stayed 0, now XTab, while activeIndex followed TabB to
// 2. With fewer tabs it could point past the end.
// Should: previousIndex follows TabA to 1, and is null once its tab is gone.
// Native behavior this holds to: UIKit, UITabBarController.viewControllers:
// "When changing the view controllers, the tab bar controller remembers the
// view controller object that was previously selected and attempts to
// reselect it." The active tab is followed by its object, not its position,
// so the previous one is too, and both name tabs of the same list.
void main() {
  testWidgets('previousIndex follows its tab when a tab is added in front', (
    tester,
  ) async {
    final routes = ValueNotifier<List<PageRouteInfo>>(const [
      NamedRoute('TabA'),
      NamedRoute('TabB'),
    ]);
    addTearDown(routes.dispose);
    final router = _buildRouter(routes);
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    expect(tabs.previousIndex, 0);

    routes.value = const [
      NamedRoute('XTab'),
      NamedRoute('TabA'),
      NamedRoute('TabB'),
    ];
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 2);
    expect(tabs.previousIndex, 1);
  });

  testWidgets('previousIndex is null once its tab leaves the tabs', (
    tester,
  ) async {
    final routes = ValueNotifier<List<PageRouteInfo>>(const [
      NamedRoute('TabA'),
      NamedRoute('TabB'),
      NamedRoute('XTab'),
    ]);
    addTearDown(routes.dispose);
    final router = _buildRouter(routes);
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(2);
    await tester.pumpAndSettle();
    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();
    expect(tabs.previousIndex, 2);

    routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 1);
    expect(tabs.previousIndex, isNull);
  });
}

RootStackRouter _buildRouter(ValueNotifier<List<PageRouteInfo>> routes) =>
    .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => ValueListenableBuilder(
            valueListenable: routes,
            builder: (_, value, _) => AutoTabsRouter(routes: value),
          ),
          children: [
            for (final (name, path) in [
              ('TabA', 'a'),
              ('TabB', 'b'),
              ('XTab', 'x'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => Center(child: Text(name)),
              ),
          ],
        ),
      ],
    );
