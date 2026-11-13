import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Navigating to the tab on screen while another tab's guard decides calls
// off the change to that other tab.
// Setup: tabs [TabA, TabB, TabC]; TabB's guard takes its time.
// Steps: on TabA, choose TabB; nothing shows yet. Navigate to TabA, as a
// notification handler does. The guard then lets TabB in.
// Was: TabB showed, though TabA was navigated to last. A navigation to the
// active tab updated it without touching the waiting change.
// Should: TabA stays; the change to TabB is called off, as choosing TabC
// calls it off (the control).
// What this holds to: the navigation made last wins. On the web a
// navigation is canceled by "another navigation starting" (MDN,
// NavigateEvent.signal). setActiveIndex with the active index is not a new
// choice: Flutter's TabController ignores a choice of the selected tab
// (TabController._changeIndex), the tabs views echo the active index while a
// guard decides, and tab_guards_test.dart pins that the waiting change goes
// on then.
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: navigating to the active tab while a guard decides stays',
      (tester) async {
        final (router, decision) = await _pumpTabs(tester, kind);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();

        unawaited(
          router.navigate(
            const NamedRoute('HomeRoute', children: [NamedRoute('TabA')]),
          ),
        );
        await tester.pumpAndSettle();
        decision.complete(true);
        await tester.pumpAndSettle();

        expect(tabs.activeIndex, 0);
        expect(find.text('TabA').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/a');
      },
    );
  }

  testWidgets('control: another tab chosen while a guard decides stays', (
    tester,
  ) async {
    final (router, decision) = await _pumpTabs(tester, .indexedStack);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();

    tabs.setActiveIndex(2);
    await tester.pumpAndSettle();
    decision.complete(true);
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 2);
    expect(find.text('TabC'), findsOneWidget);
  });
}

enum _Tabs { indexedStack, pageView, tabBar }

// Shows the tabs and returns the router with the completer TabB's guard waits
// for: completed with whether the guard lets TabB in.
Future<(RootStackRouter, Completer<bool>)> _pumpTabs(
  WidgetTester tester,
  _Tabs kind,
) async {
  // Made here, inside the test's fake clock, so pumping completes it.
  final decision = Completer<bool>();
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
            .indexedStack => const AutoTabsRouter(routes: routes),
            .pageView => const AutoTabsRouter.pageView(routes: routes),
            .tabBar => const AutoTabsRouter.tabBar(routes: routes),
          },
        ),
        children: [
          for (final name in ['TabA', 'TabB', 'TabC'])
            NamedRouteDef(
              name: name,
              path: name.substring(3).toLowerCase(),
              guards: [
                if (name == 'TabB')
                  AutoRouteGuard.simple((resolver, _) async {
                    if (await decision.future) {
                      resolver.next();
                    } else {
                      resolver.reject();
                    }
                  }),
              ],
              builder: (_, _) => Center(child: Text(name)),
            ),
        ],
      ),
    ],
  );
  await pumpRouterApp(tester, router);
  return (router, decision);
}
