import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Once a tab change is replaced by another, its later guards are not asked.
// Headless test:
// auto_route/test/nested_tabs_router/replaced_change_skips_later_guards_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaced change skips later guards', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs TabA, TabB and TabC. TabB's first guard waits for a
      // check, and its second sends the user to a login page. Tap 'Open tab
      // B', then 'Open tab C'. The check then lets TabB in.
      // Was: the login page opened over TabC.
      // Should: TabC stays, as on the web a navigation that another one
      // replaces is canceled.
      testWidgets(
        '${kind.name}: the later guards of a replaced tab change are not asked',
        (tester) async {
          final check = Completer<bool>();
          var loginGuardCalls = 0;
          const routes = [
            NamedRoute<Object?>('TabA'),
            NamedRoute<Object?>('TabB'),
            NamedRoute<Object?>('TabC'),
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
                  for (final name in ['TabA', 'TabB', 'TabC'])
                    NamedRouteDef(
                      name: name,
                      path: name.substring(3).toLowerCase(),
                      guards: [
                        if (name == 'TabB') ...[
                          AutoRouteGuard.simple((resolver, _) async {
                            if (await check.future) {
                              resolver.next();
                            } else {
                              resolver.reject();
                            }
                          }),
                          AutoRouteGuard.simple((resolver, _) {
                            loginGuardCalls++;
                            unawaited(
                              resolver.redirectUntil(
                                const NamedRoute('LoginRoute'),
                              ),
                            );
                          }),
                        ],
                      ],
                      builder: (context, _) => SafeArea(
                        child: Column(
                          children: [
                            Text(name),
                            TextButton(
                              onPressed: () =>
                                  context.tabsRouter.setActiveIndex(1),
                              child: const Text('Open tab B'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  context.tabsRouter.setActiveIndex(2),
                              child: const Text('Open tab C'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              NamedRouteDef(
                name: 'LoginRoute',
                path: '/login',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('LoginRoute'))),
              ),
            ],
          );
          await pumpRouterApp(tester, router);

          await tester.tap(find.text('Open tab B').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open tab C').hitTestable());
          await tester.pumpAndSettle();

          check.complete(true);
          await tester.pumpAndSettle();

          expect(find.text('LoginRoute'), findsNothing);
          expect(loginGuardCalls, 0);
          expect(find.text('TabC').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/c');
        },
      );
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }
