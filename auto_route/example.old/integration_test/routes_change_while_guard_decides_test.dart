import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// When the tabs list changes while a tab's guard still decides, the tab that
// guard was asked about is the one that shows once it lets it in.
// Headless test:
// auto_route/test/nested_tabs_router/routes_change_while_guard_decides_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('routes change while guard decides', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs Feed and Profile. Profile's guard waits. Tap 'Open
      // profile', then 'Sign in', which adds an Orders tab before Profile.
      // Orders' guard rejects. Profile's guard then lets it in.
      // Was: Orders showed, its guard never asked.
      // Should: Profile shows, as UIKit's tab bar controller follows the
      // selected view controller, not its index, when its tabs change.
      testWidgets(
        '${kind.name}: a tab added before the tab whose guard decides does '
        'not show in its place',
        (tester) async {
          final decision = Completer<bool>();
          var ordersGuardCalls = 0;
          final routes = ValueNotifier<List<PageRouteInfo>>(const [
            NamedRoute('FeedTab'),
            NamedRoute('ProfileTab'),
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
                    builder: (_, value, _) => switch (kind) {
                      .indexedStack => AutoTabsRouter(routes: value),
                      .pageView => AutoTabsRouter.pageView(routes: value),
                      .tabBar => AutoTabsRouter.tabBar(routes: value),
                    },
                  ),
                ),
                children: [
                  NamedRouteDef(
                    name: 'FeedTab',
                    path: 'feed',
                    builder: (context, _) => SafeArea(
                      child: Column(
                        children: [
                          const Text('FeedTab'),
                          TextButton(
                            onPressed: () =>
                                context.tabsRouter.setActiveIndex(1),
                            child: const Text('Open profile'),
                          ),
                          TextButton(
                            onPressed: () => routes.value = const [
                              NamedRoute('FeedTab'),
                              NamedRoute('OrdersTab'),
                              NamedRoute('ProfileTab'),
                            ],
                            child: const Text('Sign in'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  NamedRouteDef(
                    name: 'OrdersTab',
                    path: 'orders',
                    guards: [
                      AutoRouteGuard.simple((resolver, _) {
                        ordersGuardCalls++;
                        resolver.reject();
                      }),
                    ],
                    builder: (_, _) => const Center(child: Text('OrdersTab')),
                  ),
                  NamedRouteDef(
                    name: 'ProfileTab',
                    path: 'profile',
                    guards: [
                      AutoRouteGuard.simple((resolver, _) async {
                        if (await decision.future) {
                          resolver.next();
                        } else {
                          resolver.reject();
                        }
                      }),
                    ],
                    builder: (_, _) => const Center(child: Text('ProfileTab')),
                  ),
                ],
              ),
            ],
          );
          await pumpRouterApp(tester, router);

          await tester.tap(find.text('Open profile').hitTestable());
          await tester.pumpAndSettle();
          expect(find.text('FeedTab').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Sign in').hitTestable());
          await tester.pumpAndSettle();
          decision.complete(true);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('ProfileTab').hitTestable(), findsOneWidget);
          expect(find.text('OrdersTab').hitTestable(), findsNothing);
          expect(ordersGuardCalls, 0);
          expect(router.urlState.url, '/profile');
        },
      );
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }
