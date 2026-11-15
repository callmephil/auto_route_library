import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A tab that keeps no state and whose nested router has no initial child
// shows its listed pages when it is opened again.
// Headless test: auto_route/test/nested_tabs_router/
// dropped_tab_without_initial_child_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('dropped tab without initial child', () {
    for (final kind in ['indexedStack', 'pageView', 'tabBar']) {
      // Steps: the tabs FeedTab and ProfileTab, ProfileTab listed with Info
      // and Orders, keeping no state, with no page at its path ''. Tap 'Open
      // profile', then 'Open feed', then 'Open profile' again.
      // Was: ProfileTab showed no page at all.
      // Should: Orders shows, on top of Info, as a tab of an Android bottom
      // navigation always opens on its start destination.
      testWidgets('$kind: a tab opened again shows its listed pages', (
        tester,
      ) async {
        const routes = [
          NamedRoute<Object?>('FeedTab'),
          NamedRoute<Object?>(
            'ProfileTab',
            children: [NamedRoute('ProfileInfo'), NamedRoute('ProfileOrders')],
          ),
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
                  'pageView' => const AutoTabsRouter.pageView(routes: routes),
                  'tabBar' => const AutoTabsRouter.tabBar(routes: routes),
                  _ => const AutoTabsRouter(routes: routes),
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

        await tester.tap(find.text('Open profile').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open feed').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open profile').hitTestable());
        await tester.pumpAndSettle();

        expect(find.text('ProfileOrders').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/profile/orders');
        await expectBrowserUrl('/profile/orders');
      });
    }
  });
}
