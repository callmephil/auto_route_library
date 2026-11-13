import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// In AutoTabsRouter.tabBar a change of the tabs list while the view still
// moves leaves the view on the tab the router names, as Flutter's TabBarView
// jumps to a new controller's index.
// Headless test: auto_route/test/nested_tabs_router/tab_bar_list_change_during_move_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('tab bar list change during a move', () {
    // Steps: the tabs FeedTab, ProfileTab and SettingsTab. Choose SettingsTab.
    // 100 ms later, while the view moves, rebuild the tabs without it.
    // Was: the view rested on a blank page while the router named FeedTab.
    // Should: FeedTab shows.
    testWidgets('The view rests on the tab the router names', (tester) async {
      final routes = ValueNotifier<List<PageRouteInfo>>(const [
        NamedRoute<Object?>('FeedTab'),
        NamedRoute<Object?>('ProfileTab'),
        NamedRoute<Object?>('SettingsTab'),
      ]);
      addTearDown(routes.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => Scaffold(
              body: ValueListenableBuilder(
                valueListenable: routes,
                builder: (_, tabRoutes, _) =>
                    AutoTabsRouter.tabBar(routes: tabRoutes),
              ),
            ),
            children: [
              for (final name in const ['FeedTab', 'ProfileTab', 'SettingsTab'])
                NamedRouteDef(
                  name: name,
                  path: name.toLowerCase(),
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
      await tester.pump(const Duration(milliseconds: 100));

      routes.value = const [
        NamedRoute<Object?>('FeedTab'),
        NamedRoute<Object?>('ProfileTab'),
      ];
      await tester.pumpAndSettle();

      expect(tabs.current.name, 'FeedTab');
      expect(find.text('FeedTab').hitTestable(), findsOneWidget);
    });
  });
}
