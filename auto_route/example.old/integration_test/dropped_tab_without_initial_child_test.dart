import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A tab that keeps no state and whose nested router has no initial child
// shows a page when it is opened again.
// Headless test: auto_route/test/nested_tabs_router/
// dropped_tab_without_initial_child_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('dropped tab without initial child', () {
    for (final kind in ['indexedStack', 'pageView', 'tabBar']) {
      for (final listsPages in [true, false]) {
        // Steps: the tabs FeedTab and ProfileTab, keeping no state, with no
        // page at its path ''. ProfileTab is listed with Info and Orders, or
        // with no pages. Tap 'Open profile' (or 'Open the profile link',
        // which opens '/profile/orders', when it is listed with none), then
        // 'Open feed', then 'Open profile' again.
        // Was: ProfileTab showed no page at all.
        // Should: Orders shows, as a tab of an Android bottom navigation
        // always opens on its start destination.
        testWidgets(
          '$kind, ${listsPages ? 'listed with pages' : 'listed '
                    'with none'}: a tab opened again shows a page',
          (
            tester,
          ) async {
            final routes = [
              const NamedRoute<Object?>('FeedTab'),
              if (listsPages)
                const NamedRoute<Object?>(
                  'ProfileTab',
                  children: [
                    NamedRoute('ProfileInfo'),
                    NamedRoute('ProfileOrders'),
                  ],
                )
              else
                const NamedRoute<Object?>('ProfileTab'),
            ];
            Widget page(String name, String label, int index) => SafeArea(
              child: Builder(
                builder: (context) => Column(
                  children: [
                    Text(name),
                    TextButton(
                      onPressed: () => context.tabsRouter.setActiveIndex(index),
                      child: Text(label),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        context.router.root.navigatePath('/profile/orders'),
                      ),
                      child: const Text('Open the profile link'),
                    ),
                  ],
                ),
              ),
            );
            final router = RootStackRouter.build(
              routes: [
                NamedRouteDef(
                  name: 'HomeRoute',
                  path: '/',
                  builder: (_, _) => Scaffold(
                    body: switch (kind) {
                      'pageView' => AutoTabsRouter.pageView(routes: routes),
                      'tabBar' => AutoTabsRouter.tabBar(routes: routes),
                      _ => AutoTabsRouter(routes: routes),
                    },
                  ),
                  children: [
                    NamedRouteDef(
                      name: 'FeedTab',
                      path: 'feed',
                      builder: (_, _) => page('FeedTab', 'Open profile', 1),
                    ),
                    NamedRouteDef(
                      name: 'ProfileTab',
                      path: 'profile',
                      maintainState: false,
                      builder: (_, _) => const AutoRouter(),
                      children: [
                        for (final (name, path) in [
                          ('ProfileInfo', 'info'),
                          ('ProfileOrders', 'orders'),
                        ])
                          NamedRouteDef(
                            name: name,
                            path: path,
                            builder: (_, _) => page(name, 'Open feed', 0),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            );
            await pumpRouterApp(tester, router);

            await tester.tap(
              find
                  .text(listsPages ? 'Open profile' : 'Open the profile link')
                  .hitTestable(),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Open feed').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Open profile').hitTestable());
            await tester.pumpAndSettle();

            expect(find.text('ProfileOrders').hitTestable(), findsOneWidget);
            expect(router.urlState.url, '/profile/orders');
            await expectBrowserUrl('/profile/orders');
          },
        );
      }
    }
  });
}
