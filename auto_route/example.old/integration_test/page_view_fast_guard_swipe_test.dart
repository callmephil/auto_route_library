import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// In AutoTabsRouter.pageView a swipe to a tab whose async guard lets it in
// at once ends on that tab, as Flutter's PageView ends a fling on the page
// it reached.
// Headless test: auto_route/test/nested_tabs_router/page_view_fast_guard_swipe_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('page view fast guard swipe', () {
    // Steps: the tabs TabA and TabB. TabB's guard awaits a value ready at
    // once, then lets the tab in. Swipe from TabA to TabB.
    // Was: the view slid back to TabA while TabB was the active tab.
    // Should: TabB shows.
    testWidgets('A swipe to a tab its guard lets in at once shows it', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: AutoTabsRouter.pageView(routes: _kTabs)),
            children: [
              NamedRouteDef(
                name: 'TabA',
                path: 'a',
                builder: (_, _) => const Center(child: Text('TabA')),
              ),
              NamedRouteDef(
                name: 'TabB',
                path: 'b',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    await Future<void>.value();
                    resolver.next();
                  }),
                ],
                builder: (_, _) => const Center(child: Text('TabB')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

      await swipeToNextPage(tester, find.text('TabA'));
      await tester.pumpAndSettle();

      expect(tabs.activeIndex, 1);
      expect(find.text('TabB').hitTestable(), findsOneWidget);
      expect(find.text('TabA').hitTestable(), findsNothing);
    });
  });
}

const _kTabs = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('TabB')];
