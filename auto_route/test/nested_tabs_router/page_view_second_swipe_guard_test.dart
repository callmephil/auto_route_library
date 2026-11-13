import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// In AutoTabsRouter.pageView, the active tab stays on screen while the guard
// of a tab swiped to still decides, also on a second swipe.
// Steps: tabs [TabA, TabB], TabB's guard takes its time. Swipe to TabB: the
// view goes back to TabA. Swipe to TabB again, then let the guard accept.
// Was: after the second swipe the view rested on TabB's empty page, with
// TabA, still the active tab, off screen until the guard answered. Asking
// again for a tab whose guards decide doesn't notify, and the page view
// never checked where the scroll ended.
// Native behavior this holds to: the README, "Until then, and when they
// reject, the current tab stays"; a tab UITabBarController's
// tabBarController(_:shouldSelect:) refuses leaves the selected tab on
// screen. The tabBar kind is a control: it already checked.
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a second swipe to a tab whose guard decides keeps the '
      'active tab on screen',
      (tester) async {
        Completer<bool>? decision;
        const routes = [
          NamedRoute<Object?>('TabA'),
          NamedRoute<Object?>('TabB'),
        ];
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => Scaffold(
                body: switch (kind) {
                  .pageView => const AutoTabsRouter.pageView(routes: routes),
                  .tabBarControl => const AutoTabsRouter.tabBar(routes: routes),
                },
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
                    AutoRouteGuard.simple((resolver, _) async {
                      if (await decision!.future) {
                        resolver.next();
                      } else {
                        resolver.reject();
                      }
                    }),
                  ],
                  builder: (_, _) => const Center(child: Text('TabB')),
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
        decision = Completer<bool>();

        // The active tab and how many TabA's are on screen after the swipe.
        Future<(int, int)> swipeToTabB() async {
          await tester.fling(find.text('TabA'), const Offset(-400, 0), 1000);
          await tester.pumpAndSettle();
          return (
            tabs.activeIndex,
            find.text('TabA').hitTestable().evaluate().length,
          );
        }

        final afterEachSwipe = [
          for (var swipe = 0; swipe < 2; swipe++) await swipeToTabB(),
        ];
        expect(afterEachSwipe, [(0, 1), (0, 1)]);
        expect(find.text('TabB'), findsNothing);

        decision.complete(true);
        await tester.pumpAndSettle();
        expect(tabs.activeIndex, 1);
        expect(find.text('TabB').hitTestable(), findsOneWidget);
      },
    );
  }
}

enum _Tabs { pageView, tabBarControl }
