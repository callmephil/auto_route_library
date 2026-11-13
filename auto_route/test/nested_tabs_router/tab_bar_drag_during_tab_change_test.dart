import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// In AutoTabsRouter.tabBar, a drag that catches the view while it moves to
// a chosen tab, and lets go over a tab whose guard rejects, raises no error
// and ends on the chosen tab.
// Steps: tabs [TabA, TabB, TabC]; TabB's guard rejects. On TabA, choose
// TabC, and within the first frames of the move drag the view by 250
// pixels toward TabA and let go. The same from TabC toward TabA, dragging
// toward TabC.
// Was: "Failed assertion: '!indexIsChanging'" from TabController.offset.
// The view handed the tab under the finger to the tab bar, TabB's guard
// rejected it, and the tab bar started its animation back to the active
// tab; the view then set the tab bar's offset, which TabController refuses
// while it animates. At the drag's end the view set the offset to zero the
// same way.
// Native behavior this holds to: Flutter's TabBarView sets the offset only
// while the TabController's index isn't changing.
void main() {
  for (final (start, chosen, dx) in [
    ('/a', 'TabC', 250.0),
    ('/c', 'TabA', -250.0),
  ]) {
    testWidgets('from $start to $chosen, a drag by $dx during the move ends on '
        '$chosen without an error', (tester) async {
      final router = _buildRouter();
      await pumpRouterApp(tester, router, initialLink: start);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
      final chosenIndex = _kTabNames.indexOf(chosen);

      tabs.setActiveIndex(chosenIndex);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Scaffold)),
      );
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(Offset(dx / 5, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tabs.activeIndex, chosenIndex);
      expect(find.text(chosen).hitTestable(), findsOneWidget);
      expect((_tabBar.index, _tabBar.offset), (chosenIndex, 0.0));
    });
  }
}

const _kTabNames = ['TabA', 'TabB', 'TabC'];

// The tab bar's controller, as the tabs last built it.
late TabController _tabBar;

RootStackRouter _buildRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => Scaffold(
        body: AutoTabsRouter.tabBar(
          routes: [for (final name in _kTabNames) NamedRoute<Object?>(name)],
          builder: (_, child, controller) {
            _tabBar = controller;
            return child;
          },
        ),
      ),
      children: [
        for (final name in _kTabNames)
          NamedRouteDef(
            name: name,
            path: name.substring(3).toLowerCase(),
            guards: [
              if (name == 'TabB')
                AutoRouteGuard.simple((resolver, _) => resolver.reject()),
            ],
            builder: (_, _) => Center(child: Text(name)),
          ),
      ],
    ),
  ],
);
