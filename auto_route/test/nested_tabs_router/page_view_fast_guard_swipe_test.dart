import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A swipe to a tab whose guard is async and lets it in at once ends on
// that tab.
// Steps: AutoTabsRouter.pageView with TabA and TabB; TabB's guard awaits a
// value that is ready at once, as a guard that reads a cached session does,
// then lets the tab in. On TabA, fling toward TabB.
// Was: the page view slid back to TabA while the router said TabB was
// active. Halfway through the swipe the router notified with TabA still
// active, since the guard was deciding, and the view started back to TabA.
// The guard's yes came while the page still read as TabB, so nothing turned
// the view around.
// Native behavior this holds to: Flutter's PageView ends a fling on the
// page it reached, and the README's tab guards show the tab once they let
// it in. AutoTabsRouter.tabBar is a control: it already ends on TabB.
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a swipe to a tab whose async guard says yes at once '
      'ends on that tab',
      (tester) => _expectSwipeEndsOnGuardedTab(tester, kind),
    );
  }
}

Future<void> _expectSwipeEndsOnGuardedTab(
  WidgetTester tester,
  _Tabs kind,
) async {
  const routes = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('TabB')];
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .pageView => const AutoTabsRouter.pageView(routes: routes),
            .tabBar => const AutoTabsRouter.tabBar(routes: routes),
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
  await pumpRouterApp(tester, router, initialLink: '/a');
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

  await tester.fling(find.text('TabA'), const Offset(-400, 0), 1000);
  await tester.pumpAndSettle();

  expect(tabs.activeIndex, 1);
  expect(find.text('TabB').hitTestable(), findsOneWidget);
  expect(router.urlState.url, '/b');
}

enum _Tabs { pageView, tabBar }
