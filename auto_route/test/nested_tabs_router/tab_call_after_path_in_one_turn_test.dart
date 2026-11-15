import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A path or a root navigate into an open tabs page, then a tab call in the
// same handler: the later call wins, for every kind of tabs. The bug, the
// path winning, is on dev; feae9806 fixed it on the way and pinned it for the
// default tabs and a path in test/navigate_reaches_nested_router_in_call_test
// .dart. This file pins the neighbors.
// Setup: the tabs FeedTab and ProfileTab, path 'profile', on Feed.
// Steps: navigatePath to '/profile', or navigate to HomeRoute with
// ProfileTab, then setActiveIndex with 0, with no await between them.
// Should: Feed, with no guard, with a root guard that answers in its call and
// with a guard on ProfileTab that answers in its call.
// Not pinned here, decided earlier and the same a frame apart:
// - A guard on ProfileTab that answers later: Profile shows once it does.
//   While it decides, Feed is the active tab, and setActiveIndex with the
//   active index calls nothing off, as Flutter's TabController ignores a
//   choice of the selected tab (round 1, T16).
// - A link from the platform: it reaches the app in a later engine message,
//   so it comes after the call and wins.
// Native behavior this holds to: a TabController's index is the one set
// last, and on iOS a UITabBarController's selectedIndex set twice in one run
// loop turn ends on the second.
void main() {
  for (final kind in _Tabs.values) {
    for (final guards in _Guards.values) {
      for (final byPath in [true, false]) {
        testWidgets('${kind.name}, ${guards.name}: setActiveIndex right after '
            '${byPath ? 'navigatePath' : 'a root navigate'} wins', (
          tester,
        ) async {
          final router = _buildRouter(kind, guards);
          await pumpRouterApp(tester, router);
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

          unawaited(
            byPath
                ? router.navigatePath('/profile')
                : router.navigate(
                    const NamedRoute(
                      'HomeRoute',
                      children: [NamedRoute('ProfileTab')],
                    ),
                  ),
          );
          tabs.setActiveIndex(0);
          await tester.pumpAndSettle();

          expect(tabs.activeIndex, 0);
          expect(find.text('FeedTab').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/feed');
        });
      }
    }
  }
}

enum _Tabs { indexedStack, pageView, tabBar, builder }

enum _Guards { none, rootGuardAtOnce, tabGuardAtOnce }

final _atOnce = AutoRouteGuard.simple((resolver, _) => resolver.next());

RootStackRouter _buildRouter(_Tabs kind, _Guards guards) {
  const routes = [
    NamedRoute<Object?>('FeedTab'),
    NamedRoute<Object?>('ProfileTab'),
  ];
  return .build(
    guards: [if (guards == .rootGuardAtOnce) _atOnce],
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .indexedStack => const AutoTabsRouter(routes: routes),
            .pageView => const AutoTabsRouter.pageView(routes: routes),
            .tabBar => const AutoTabsRouter.tabBar(routes: routes),
            .builder => AutoTabsRouter.builder(
              routes: routes,
              builder: (_, children, tabs) =>
                  IndexedStack(index: tabs.activeIndex, children: children),
            ),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'FeedTab',
            path: 'feed',
            builder: (_, _) => const Center(child: Text('FeedTab')),
          ),
          NamedRouteDef(
            name: 'ProfileTab',
            path: 'profile',
            guards: [if (guards == .tabGuardAtOnce) _atOnce],
            builder: (_, _) => const Center(child: Text('ProfileTab')),
          ),
        ],
      ),
    ],
  );
}
