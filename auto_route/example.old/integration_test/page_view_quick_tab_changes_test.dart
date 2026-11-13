import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// In AutoTabsRouter.pageView two quick tab changes show only the tab left
// and the tabs chosen, as UITabBarController and Android's
// BottomNavigationView never show the tabs between.
// Headless test: auto_route/test/nested_tabs_router/page_view_quick_tab_changes_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('page view quick tab changes', () {
    // Steps: the five tabs TabA to TabE, every page built. Starting on TabA
    // choose TabE and then TabC at once, noting the tabs on screen each frame.
    // Was: TabD showed during the move.
    // Should: only TabA, TabE and TabC show, and the view rests on TabC.
    testWidgets('Two quick tab changes show no other tab', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => Scaffold(
              body: AutoTabsRouter.pageView(
                routes: [
                  for (final name in _kTabNames) NamedRoute<Object?>(name),
                ],
                lazyLoad: false,
              ),
            ),
            children: [
              for (final name in _kTabNames)
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
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
      final seen = <String>{};

      tabs
        ..setActiveIndex(4)
        ..setActiveIndex(2);
      for (var frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        seen.addAll(_onScreen(tester));
      }
      await tester.pumpAndSettle();

      expect(seen.difference({'TabA', 'TabE', 'TabC'}), isEmpty);
      expect(_onScreen(tester), {'TabC'});
    });
  });
}

const _kTabNames = ['TabA', 'TabB', 'TabC', 'TabD', 'TabE'];

// The tabs whose text has its center on screen.
Set<String> _onScreen(WidgetTester tester) {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return {
    for (final name in _kTabNames)
      for (final element in find.text(name, skipOffstage: false).evaluate())
        if (element.renderObject case final RenderBox box
            when box.attached && box.hasSize)
          if (box.localToGlobal(box.size.center(.zero)).dx case final dx
              when dx >= 0 && dx <= width)
            name,
  };
}
