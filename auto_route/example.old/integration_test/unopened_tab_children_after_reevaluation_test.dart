import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A tab not opened yet keeps the pages it is to open with when the guards
// are reevaluated meanwhile.
// Headless test: auto_route/test/nested_tabs_router/
// unopened_tab_children_after_reevaluation_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('unopened tab children after reevaluation', () {
    for (final kind in ['indexedStack', 'pageView', 'tabBar']) {
      // Steps: tabs FeedTab and ProfileTab, listed with Info and Orders, and
      // a reevaluateListenable. ProfileTab was never opened. Tap 'Refresh
      // token', which makes the listenable fire, then 'Open profile'.
      // Was: ProfileTab opened on Info alone.
      // Should: Orders shows, on top of Info, as Android's bottom navigation
      // keeps the back stack of a tab not shown.
      testWidgets('$kind: a tab opened after a reevaluation shows its listed '
          'pages', (tester) async {
        final token = ValueNotifier(0);
        addTearDown(token.dispose);
        const routes = [
          NamedRoute<Object?>('FeedTab'),
          NamedRoute<Object?>(
            'ProfileTab',
            children: [NamedRoute('ProfileInfo'), NamedRoute('ProfileOrders')],
          ),
        ];
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
                  builder: (context, _) => SafeArea(
                    child: Column(
                      children: [
                        const Text('FeedTab'),
                        TextButton(
                          onPressed: () => token.value++,
                          child: const Text('Refresh token'),
                        ),
                        TextButton(
                          onPressed: () => context.tabsRouter.setActiveIndex(1),
                          child: const Text('Open profile'),
                        ),
                      ],
                    ),
                  ),
                ),
                NamedRouteDef(
                  name: 'ProfileTab',
                  path: 'profile',
                  builder: (_, _) => const AutoRouter(),
                  children: [
                    for (final (name, path) in [
                      ('ProfileInfo', ''),
                      ('ProfileOrders', 'orders'),
                    ])
                      NamedRouteDef(
                        name: name,
                        path: path,
                        builder: (_, _) => SafeArea(child: Text(name)),
                      ),
                  ],
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: token);

        await tester.tap(find.text('Refresh token').hitTestable());
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
