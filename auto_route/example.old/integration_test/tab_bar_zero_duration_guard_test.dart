import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// AutoTabsRouter.tabBar(duration: Duration.zero) jumps back to the active
// tab when a swipe ends on a tab its guard rejects, as Flutter's TabBarView
// jumps when its duration is zero.
// Headless test: auto_route/test/nested_tabs_router/tab_bar_zero_duration_guard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('tab bar zero duration guard', () {
    // Steps: the tabs TabA and TabB with a zero duration, and TabB's guard
    // rejects. Swipe from TabA to TabB.
    // Was: the assertion "duration > Duration.zero" failed, and TabB's empty
    // page stayed on screen.
    // Should: no error, and TabA shows.
    testWidgets('A swipe to a rejected tab with a zero duration goes back', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter.tabBar(
                routes: [
                  NamedRoute<Object?>('TabA'),
                  NamedRoute<Object?>('TabB'),
                ],
                duration: .zero,
              ),
            ),
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
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
                ],
                builder: (_, _) => const Center(child: Text('TabB')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router);

      await tester.fling(find.text('TabA'), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 0);
      expect(find.text('TabA').hitTestable(), findsOneWidget);
    });
  });
}
