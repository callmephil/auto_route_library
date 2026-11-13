import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// In a right-to-left app, and with vertical tabs, a drag toward a tab not
// opened yet shows that tab's page as it comes in.
// Steps: AutoTabsRouter.pageView or .tabBar with three lazy tabs, in a
// right-to-left app or with scrollDirection: Axis.vertical. Drag the first
// tab toward the second, less than half way: right to left the finger moves
// right, vertically it moves up.
// Was: the drag uncovered blank space. The views picked the tab to load from
// the drag's horizontal movement alone: right to left that is the wrong
// neighbor, and a vertical drag has none.
// Native behavior this holds to: Flutter's PageView, and the TabBarView
// built on it, build each page as it scrolls into view, whatever the text
// direction or the axis. The left-to-right tests are controls
// (test/shell/swipe_unopened_tab_content_test.dart).
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: right to left, the tab a drag uncovers shows its page',
      (tester) async {
        final router = await _pumpTabs(tester, kind, direction: .rtl);
        final start = tester.getCenter(find.text('TabA'));
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(200, 0));
        await tester.pump();

        // The first tab moved right, so the second is coming in on the left.
        expect(tester.getCenter(find.text('TabA')).dx, greaterThan(start.dx));
        expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 0);
        expect(find.text('TabB'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '${kind.name}: vertical, the tab a drag uncovers shows its page',
      (tester) async {
        final router = await _pumpTabs(tester, kind, axis: .vertical);
        final start = tester.getCenter(find.text('TabA'));
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump();

        // The first tab moved up, so the second is coming in from below.
        expect(tester.getCenter(find.text('TabA')).dy, lessThan(start.dy));
        expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 0);
        expect(find.text('TabB'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('${kind.name}: left to right, the tab a drag '
        'uncovers shows its page', (tester) async {
      final router = await _pumpTabs(tester, kind);
      final start = tester.getCenter(find.text('TabA'));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();

      expect(tester.getCenter(find.text('TabA')).dx, lessThan(start.dx));
      expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 0);
      expect(find.text('TabB'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  }
}

enum _Tabs { pageView, tabBar }

Future<RootStackRouter> _pumpTabs(
  WidgetTester tester,
  _Tabs kind, {
  TextDirection direction = .ltr,
  Axis axis = .horizontal,
}) async {
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
        builder: (_, _) => Scaffold(
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
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router.config(),
      builder: (_, child) =>
          Directionality(textDirection: direction, child: child!),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
