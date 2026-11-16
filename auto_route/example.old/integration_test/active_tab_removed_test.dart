import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// When the active tab is taken out of the tabs list, the url and system back
// follow the tab that shows instead.
// Headless test: auto_route/test/nested_tabs_router/active_tab_removed_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('active tab removed', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs [A, B, C], each with its own stack. Tap 'Push A2' in tab
      // A, then 'Open tab C', then 'Drop tab C', which rebuilds the tabs as
      // [A, B]. Tab A shows on A2. Press system back.
      // Was: the url stayed '/c', and on Android 13 and later back closed the
      // app.
      // Should: the url is '/a/2', and back pops A2, as Android's back pops
      // the page on top of the tab on screen. In a browser C's entry leaves
      // the way back: the browser steps back to the entry of A2, so the back
      // button never shows '/c' again.
      testWidgets(
        '${kind.name}: the url and back follow the tab shown after the active '
        'tab is removed',
        (tester) async {
          final routes = ValueNotifier<List<PageRouteInfo>>(const [
            NamedRoute('TabA'),
            NamedRoute('TabB'),
            NamedRoute('TabC'),
          ]);
          addTearDown(routes.dispose);
          final router = _buildRouter(kind, routes);
          await pumpRouterApp(tester, router);

          await tester.tap(find.text('Push A2').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open tab C').hitTestable());
          await tester.pumpAndSettle();
          expect(find.text('C1').hitTestable(), findsOneWidget);
          // The browser steps back to the entry of A2, under the one of C.
          await expectBrowserEntryAfter(-1, () async {
            await tester.tap(find.text('Drop tab C').hitTestable());
            await tester.pumpAndSettle();
          });

          expect(tester.takeException(), isNull);
          expect(find.text('A2').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/a/2');
          await expectBrowserUrl('/a/2');

          await systemBack(tester);

          expect(find.text('A1').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/a');
        },
      );
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }

RootStackRouter _buildRouter(
  _Tabs kind,
  ValueNotifier<List<PageRouteInfo>> routes,
) => .build(
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
        for (final tab in ['A', 'B', 'C'])
          AutoRoute(
            path: tab.toLowerCase(),
            page: EmptyShellRoute('Tab$tab'),
            children: [
              for (final (path, name) in [('', '${tab}1'), ('2', '${tab}2')])
                NamedRouteDef(
                  name: name,
                  path: path,
                  builder: (context, _) => SafeArea(
                    child: Column(
                      children: [
                        Text(name),
                        TextButton(
                          onPressed: () => unawaited(
                            context.router.push(const NamedRoute('A2')),
                          ),
                          child: const Text('Push A2'),
                        ),
                        TextButton(
                          onPressed: () => context.tabsRouter.setActiveIndex(2),
                          child: const Text('Open tab C'),
                        ),
                        TextButton(
                          onPressed: () => routes.value = const [
                            NamedRoute('TabA'),
                            NamedRoute('TabB'),
                          ],
                          child: const Text('Drop tab C'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  ],
);
