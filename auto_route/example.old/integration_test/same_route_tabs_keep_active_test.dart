import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Tabs built from a list, one tab per item, all of the same route, keep the
// tab on screen when the list changes.
// Headless test:
// auto_route/test/nested_tabs_router/same_route_tabs_keep_active_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('same-route tabs keep active', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs [Item 1, Item 2], one route told apart by its path param.
      // Tap 'Open item 2', then 'Add item' on Item 2.
      // Was: Item 1 showed, the first tab of that route.
      // Should: Item 2 stays on screen, as UIKit's tab bar controller
      // reselects the view controller that was selected.
      testWidgets(
        '${kind.name}: a tab added after the active one keeps the active tab',
        (tester) async {
          final ids = ValueNotifier([1, 2]);
          addTearDown(ids.dispose);
          final router = _buildRouter(kind, ids);
          await pumpRouterApp(tester, router);

          await tester.tap(find.text('Open item 2').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add item').hitTestable());
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
          expect(tabs.activeIndex, 1);
          expect(find.text('Item 2').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/item/2');
        },
      );
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }

RootStackRouter _buildRouter(_Tabs kind, ValueNotifier<List<int>> ids) =>
    .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => Scaffold(
            body: ValueListenableBuilder(
              valueListenable: ids,
              builder: (_, value, _) {
                final routes = [
                  for (final id in value)
                    NamedRoute<Object?>('ItemRoute', params: {'id': id}),
                ];
                return switch (kind) {
                  .indexedStack => AutoTabsRouter(routes: routes),
                  .pageView => AutoTabsRouter.pageView(routes: routes),
                  .tabBar => AutoTabsRouter.tabBar(routes: routes),
                };
              },
            ),
          ),
          children: [
            NamedRouteDef(
              name: 'ItemRoute',
              path: 'item/:id',
              builder: (context, data) => SafeArea(
                child: Column(
                  children: [
                    Text('Item ${data.params.getInt('id')}'),
                    TextButton(
                      onPressed: () => context.tabsRouter.setActiveIndex(1),
                      child: const Text('Open item 2'),
                    ),
                    TextButton(
                      onPressed: () =>
                          ids.value = [...ids.value, ids.value.length + 1],
                      child: const Text('Add item'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
