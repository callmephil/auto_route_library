import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Tabs of one route, one tab per list item: a link to one item's tab opens
// that tab.
// Headless test: auto_route/test/nested_tabs_router/same_route_tabs_path_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('same route tabs path', () {
    for (final kind in ['indexedStack', 'pageView', 'tabBar', 'builder']) {
      // Steps: tabs Item 1, Item 2 and Item 3 of one route, path
      // 'item/:id'. Tap 'Open item 2', then 'Open link /item/3', which calls
      // navigatePath, as a link from a notification does.
      // Was: the tab of Item 2 became Item 3.
      // Should: the third tab opens and shows Item 3, and Item 2's tab still
      // shows Item 2, as UIKit's tab bar controller selects the view
      // controller given, also among several of one class.
      testWidgets('$kind: a link to an item tab opens that tab', (
        tester,
      ) async {
        const routes = [
          NamedRoute<Object?>('ItemRoute', params: {'id': 1}),
          NamedRoute<Object?>('ItemRoute', params: {'id': 2}),
          NamedRoute<Object?>('ItemRoute', params: {'id': 3}),
        ];
        late final RootStackRouter router;
        router = RootStackRouter.build(
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
                        for (final index in [0, 1])
                          TextButton(
                            onPressed: () =>
                                context.tabsRouter.setActiveIndex(index),
                            child: Text('Open item ${index + 1}'),
                          ),
                        TextButton(
                          onPressed: () =>
                              unawaited(router.navigatePath('/item/3')),
                          child: const Text('Open link /item/3'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router);

        await tester.tap(find.text('Open item 2').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open link /item/3').hitTestable());
        await tester.pumpAndSettle();

        expect(find.text('Item 3').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/item/3');
        await expectBrowserUrl('/item/3');
        await tester.tap(find.text('Open item 2').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('Item 2').hitTestable(), findsOneWidget);
      });
    }
  });
}
