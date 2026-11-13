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
    // TabC, and while the view moves drag it back toward TabA and let go over
    // TabB.
    // Was: "Failed assertion: '!indexIsChanging'", and TabC didn't show.
    // Should: TabC shows and the tab bar marks it.
    // On a device a pump waits in real time and the screen's width varies,
    // so the test steers by what it reads: the move lasts long enough to be
    // caught, the drag starts once the tab bar's animation has begun, and the
    // finger moves until it rests over TabB. A drag let go over TabA would
    // rightly end on TabA, as Flutter's TabBarView ends a drag on the page it
    // settles on.
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
                duration: _kMove,
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
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump();
        if (tabBar!.animation!.value > 0) break;
      }
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Scaffold)),
      );
      final view = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      double page() => view.pixels / view.viewportDimension;
      final caughtAt = page();
      // Back toward TabA, until the finger rests over TabB.
      for (var step = 0; step < 20 && page() > _kLetGoAt + 0.01; step++) {
        final left = (page() - _kLetGoAt) * view.viewportDimension;
        await gesture.moveBy(Offset(left.clamp(1, 40), 0));
        await tester.pump();
      }
      // Where the finger lets go, and whether the tab bar still moves then.
      final (letGoAt, isMoving) = (page(), tabBar!.indexIsChanging);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        (caughtAt < 2, isMoving, letGoAt.round()),
        (true, true, 1),
        reason:
            'The drag caught the move at page $caughtAt and let go at '
            'page $letGoAt',
      );

      expect(tabs.activeIndex, 2);
      expect(find.text('TabC').hitTestable(), findsOneWidget);
      expect((tabBar!.index, tabBar!.offset), (2, 0.0));
    });
  });
}

const _kTabNames = ['TabA', 'TabB', 'TabC'];

// The move to the chosen tab, long enough that a busy device still catches
// it with the drag.
const _kMove = Duration(seconds: 2);

// Where the finger lets go, in pages: over TabB, on the side of TabA.
const _kLetGoAt = 0.8;
