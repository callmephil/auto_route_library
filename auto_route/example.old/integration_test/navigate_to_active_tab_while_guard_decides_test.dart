import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Navigating to the tab on screen while another tab's guard decides calls
// off the change to that other tab.
// Headless test: auto_route/test/nested_tabs_router/
// navigate_to_active_tab_while_guard_decides_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigate to active tab while guard decides', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs [TabA, TabB]; TabB's guard takes its time. Tap 'Open tab
      // B', then 'Navigate to tab A', which calls navigate. The guard then
      // lets TabB in.
      // Was: TabB showed.
      // Should: TabA stays, as on the web the navigation made last wins.
      testWidgets(
        '${kind.name}: navigating to the active tab while a guard decides '
        'stays',
        (tester) async {
          final decision = Completer<bool>();
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
                    .indexedStack => const AutoTabsRouter(routes: routes),
                    .pageView => const AutoTabsRouter.pageView(routes: routes),
                    .tabBar => const AutoTabsRouter.tabBar(routes: routes),
                  },
                ),
                children: [
                  NamedRouteDef(
                    name: 'TabA',
                    path: 'a',
                    builder: (context, _) => SafeArea(
                      child: Column(
                        children: [
                          const Text('TabA'),
                          TextButton(
                            onPressed: () =>
                                context.tabsRouter.setActiveIndex(1),
                            child: const Text('Open tab B'),
                          ),
                          TextButton(
                            onPressed: () => unawaited(
                              context.router.root.navigate(
                                const NamedRoute(
                                  'HomeRoute',
                                  children: [NamedRoute('TabA')],
                                ),
                              ),
                            ),
                            child: const Text('Navigate to tab A'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  NamedRouteDef(
                    name: 'TabB',
                    path: 'b',
                    guards: [
                      AutoRouteGuard.simple((resolver, _) async {
                        if (await decision.future) {
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

          await tester.tap(find.text('Open tab B').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Navigate to tab A').hitTestable());
          await tester.pumpAndSettle();
          decision.complete(true);
          await tester.pumpAndSettle();

          expect(find.text('TabA').hitTestable(), findsOneWidget);
          expect(find.text('TabB').hitTestable(), findsNothing);
          expect(router.urlState.url, '/a');
        },
      );
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }
