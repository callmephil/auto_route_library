import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// In a right-to-left app, and with vertical tabs, a drag toward a tab not
// opened yet shows its page as it comes in, as Flutter's PageView builds
// each page as it scrolls into view in any direction.
// Headless test: auto_route/test/shell/swipe_unopened_tab_rtl_vertical_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('swipe unopened tab rtl vertical', () {
    // Steps: three lazy tabs, right to left or vertical; drag the first tab
    // a fifth of the way toward the second and hold.
    // Was: the drag uncovered blank space.
    // Should: the second tab's page shows while it comes in.
    for (final kind in _Tabs.values) {
      // The way the finger moves, toward the second tab.
      for (final (label, direction, axis, toward) in [
        (
          'right to left',
          TextDirection.rtl,
          Axis.horizontal,
          const Offset(1, 0),
        ),
        ('vertical', TextDirection.ltr, Axis.vertical, const Offset(0, -1)),
      ]) {
        testWidgets('${kind.name}, $label: a drag shows the unopened tab', (
          tester,
        ) async {
          const routes = [
            NamedRoute<Object?>('TabA'),
            NamedRoute<Object?>('TabB'),
            NamedRoute<Object?>('TabC'),
          ];
          final router = RootStackRouter.build(
            routes: [
              NamedRouteDef(
                name: 'HomeRoute',
                path: '/',
                builder: (_, _) => Directionality(
                  textDirection: direction,
                  child: Scaffold(
                    body: switch (kind) {
                      .pageView => AutoTabsRouter.pageView(
                        routes: routes,
                        scrollDirection: axis,
                      ),
                      .tabBar => AutoTabsRouter.tabBar(
                        routes: routes,
                        scrollDirection: axis,
                      ),
                    },
                  ),
                ),
                children: [
                  for (final name in ['TabA', 'TabB', 'TabC'])
                    NamedRouteDef(
                      name: name,
                      path: name.substring(3).toLowerCase(),
                      builder: (_, _) => Center(child: Text(name)),
                    ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);
          await pumpRouterApp(tester, router);

          // A fifth of the view in two steps: short of the middle on any
          // screen. A fixed 160 px passed the middle of a screen 300 px
          // across or less, and the tabs then took the second tab.
          final view = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          final step = toward * (view.viewportDimension / 10);
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('TabA')),
          );
          await gesture.moveBy(step);
          await tester.pump();
          await gesture.moveBy(step);
          await tester.pump();

          expect(
            router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex,
            0,
          );
          expect(find.text('TabB'), findsOneWidget);

          await gesture.up();
          await tester.pumpAndSettle();
          expect(find.text('TabA').hitTestable(), findsOneWidget);
        });
      }
    }
  });
}

enum _Tabs { pageView, tabBar }
