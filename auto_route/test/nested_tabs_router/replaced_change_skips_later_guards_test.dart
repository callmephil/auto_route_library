import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Once a tab change is replaced by another, its later guards are not asked.
// Setup: tabs [TabA, TabB, TabC]. TabB has two guards: the first waits for a
// check, the second sends a user who isn't signed in to the login page.
// Steps: choose TabB; while its first guard waits, choose TabC, which shows.
// The first guard then lets TabB in.
// Was: TabB's second guard ran and opened the login page over TabC, for a
// tab change that was already replaced. TabsRouter._checkTabGuards asked the
// next guard as soon as one let the tab in, without knowing whether its
// change was still the latest.
// Should: no more guards of the replaced change are asked; TabC stays.
// Native behavior this holds to: on the web a navigation that another one
// replaces is canceled: NavigateEvent.signal "will become aborted if the
// navigation is canceled (e.g., ... another navigation starting and thus
// canceling the ongoing one)" (MDN), so its handlers stop. A single guard
// that waits and then redirects on its own can't be stopped this way.
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: the later guards of a replaced tab change are not asked',
      (tester) async {
        Completer<bool>? check;
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
                          if (await check!.future) {
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
                    builder: (_, _) => Center(child: Text(name)),
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
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
        check = Completer<bool>();

        tabs.setActiveIndex(1);
        await tester.pumpAndSettle();
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        expect(router.urlState.url, '/c');

        check.complete(true);
        await tester.pumpAndSettle();

        expect(tabs.activeIndex, 2);
        expect(
          find.text('LoginRoute'),
          findsNothing,
          reason: 'the login guard was asked $loginGuardCalls times',
        );
        expect(loginGuardCalls, 0);
        expect(find.text('TabC'), findsOneWidget);
      },
    );
  }
}

enum _Tabs { indexedStack, pageView, tabBar }
