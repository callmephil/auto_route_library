import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// AutoTabsRouter.tabBar(duration: Duration.zero) goes back to the active tab
// without an error when a swipe ends on a tab whose guard rejects.
// Steps: tabs [TabA, TabB], TabB's guard rejects; swipe from TabA to TabB.
// Was: Flutter's assertion "duration > Duration.zero" failed in debug
// builds, and the view stayed on TabB's empty page. The view went back by
// animating with the controller's duration, whatever it was.
// Native behavior this holds to: Flutter's TabBarView jumps instead of
// animating when its TabController's animationDuration is zero, and
// PageController.animateToPage needs a duration above zero. The second test
// is a control with the default duration.
void main() {
  for (final (label, duration) in [
    ('a zero duration', Duration.zero),
    ('the default duration', null),
  ]) {
    testWidgets('$label: a swipe to a tab whose guard rejects returns', (
      tester,
    ) async {
      var guardCalls = 0;
      const routes = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('TabB')];
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => Scaffold(
              body: AutoTabsRouter.tabBar(routes: routes, duration: duration),
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
                  AutoRouteGuard.simple((resolver, _) {
                    guardCalls++;
                    resolver.reject();
                  }),
                ],
                builder: (_, _) => const Center(child: Text('TabB')),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      await tester.fling(find.text('TabA'), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(guardCalls, 1);
      expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 0);
      expect(find.text('TabA').hitTestable(), findsOneWidget);
    });
  }
}
