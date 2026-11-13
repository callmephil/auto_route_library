import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Tabs of one route, one tab per list item, keep their pages when the guards
// are reevaluated.
// Headless test:
// auto_route/test/nested_tabs_router/same_route_tabs_reevaluation_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('same route tabs reevaluation', () {
    for (final kind in ['indexedStack', 'pageView', 'tabBar', 'builder']) {
      // Steps: tabs Item 1, Item 2 and Item 3 of one route, and a
      // reevaluateListenable. Tap 'Open item 2', then 'Refresh token', which
      // makes the listenable fire. Then open Item 1 and Item 3.
      // Was: Item 3 took Item 2's place, and three kinds threw "Multiple
      // widgets used the same GlobalKey".
      // Should: Item 2 stays, and each tab opens its own item, as Flutter's
      // Navigator keeps a page whose key is unchanged.
      testWidgets('$kind: a token refresh keeps each item tab', (
        tester,
      ) async {
        final token = ValueNotifier(0);
        addTearDown(token.dispose);
        const routes = [
          NamedRoute<Object?>('ItemRoute', params: {'id': 1}),
          NamedRoute<Object?>('ItemRoute', params: {'id': 2}),
          NamedRoute<Object?>('ItemRoute', params: {'id': 3}),
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
                  'builder' => AutoTabsRouter.builder(
                    routes: routes,
                    builder: (_, children, tabs) => IndexedStack(
                      index: tabs.activeIndex,
                      children: children,
                    ),
                  ),
                  _ => const AutoTabsRouter(routes: routes),
                },
              ),
              children: [
                NamedRouteDef(
                  name: 'ItemRoute',
                  path: 'item/:id',
                  builder: (context, data) => SafeArea(
                    child: Column(
                      children: [
                        Text('Item ${data.params.getInt('id')}'),
                        for (final index in [0, 1, 2])
                          TextButton(
                            onPressed: () =>
                                context.tabsRouter.setActiveIndex(index),
                            child: Text('Open item ${index + 1}'),
                          ),
                        TextButton(
                          onPressed: () => token.value++,
                          child: const Text('Refresh token'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: token);

        await tester.tap(find.text('Open item 2').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refresh token').hitTestable());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Item 2').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/item/2');
        await expectBrowserUrl('/item/2');
        await tester.tap(find.text('Open item 1').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('Item 1').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Open item 3').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('Item 3').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/item/3');
      });
    }
  });
}
