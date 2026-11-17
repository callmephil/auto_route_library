import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A tab whose guard threw once opens when it is chosen again.
// Headless test: auto_route/test/nested_tabs_router/guard_throws_tab_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('guard throws tab', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs TabA and TabB. TabB's guard awaits a check that throws
      // the first time, as a request does offline. Tap 'Open tab B', and TabA
      // stays. Tap 'Open tab B' again.
      // Was: nothing happened, and the guard was not asked again.
      // Should: the guard is asked again and TabB shows, as a navigation
      // whose handler failed is over and the next one starts anew.
      testWidgets(
        '${kind.name}: a tab whose guard threw once opens when chosen again',
        (tester) async {
          var guardCalls = 0;
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
                        ],
                      ),
                    ),
                  ),
                  NamedRouteDef(
                    name: 'TabB',
                    path: 'b',
                    guards: [
                      AutoRouteGuard.simple((resolver, _) async {
                        guardCalls++;
                        // Stands for a request that fails the first time.
                        await Future<void>.delayed(.zero);
                        if (guardCalls == 1) throw StateError('offline');
                        resolver.next();
                      }),
                    ],
                    builder: (_, _) => const Center(child: Text('TabB')),
                  ),
                ],
              ),
            ],
          );
          await pumpRouterApp(tester, router);

          // setActiveIndex returns nothing, so the guard's error is uncaught.
          // It is called here, not from a tap: since Flutter 3.50.0 the test
          // binding runs a tap's handler in the test's own zone, which reports
          // an uncaught error as a failed test, so a zone around the tap no
          // longer sees it. An app's taps never run in a test zone.
          final errors = <Object>[];
          await runZonedGuarded(() async {
            tester.element(find.text('TabA')).tabsRouter.setActiveIndex(1);
            await tester.pumpAndSettle();
          }, (error, _) => errors.add(error));
          expect(errors, [isStateError]);
          expect(find.text('TabA').hitTestable(), findsOneWidget);
          expect(router.activeGuardObserver.guardInProgress, isFalse);

          await tester.tap(find.text('Open tab B').hitTestable());
          await tester.pumpAndSettle();

          expect(guardCalls, 2);
          expect(find.text('TabB').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/b');
        },
      );
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }
