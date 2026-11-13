import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// In AutoTabsRouter.tabBar a drag that catches the view while it moves to a
// chosen tab, over a tab whose guard rejects, ends on the chosen tab without
// an error, as Flutter's TabBarView sets the tab bar's offset only while its
// index isn't changing.
// Headless test: auto_route/test/nested_tabs_router/tab_bar_drag_during_tab_change_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('tab bar drag during tab change', () {
    // Steps: tabs [TabA, TabB, TabC], TabB's guard rejects. On TabA, choose
    // TabC, and while the view moves drag it back toward TabA and let go.
    // Was: "Failed assertion: '!indexIsChanging'", and TabC didn't show.
    // Should: TabC shows and the tab bar marks it.
    testWidgets('A drag during a tab change ends on the chosen tab', (
      tester,
    ) async {
      TabController? tabBar;
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => Scaffold(
              body: AutoTabsRouter.tabBar(
                routes: [
                  for (final name in _kTabNames) NamedRoute<Object?>(name),
                ],
                builder: (_, child, controller) {
                  tabBar = controller;
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
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
        ..setActiveIndex(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Scaffold)),
      );
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tabs.activeIndex, 2);
      expect(find.text('TabC').hitTestable(), findsOneWidget);
      expect((tabBar!.index, tabBar!.offset), (2, 0.0));
    });
  });
}

const _kTabNames = ['TabA', 'TabB', 'TabC'];
