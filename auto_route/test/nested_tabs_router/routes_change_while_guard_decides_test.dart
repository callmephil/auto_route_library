import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// When the tabs list changes while a tab's guard still decides, the tab that
// guard was asked about is the one that shows once it lets it in.
// Setup: tabs [Feed, Profile]. Profile's guard waits, as one that shows a
// login does. A signed-in user also gets an Orders tab before Profile, and
// Orders has a guard that rejects.
// Steps: choose Profile with setActiveIndex(1). While its guard waits, the
// user signs in and AutoTabsRouter is rebuilt with [Feed, Orders, Profile].
// The guard then calls resolver.next().
// Was: Orders showed, the tab now at Profile's old index, though its own
// guard was never asked. With a shorter list, [Feed, Orders, Profile] to
// [Feed, Profile] while Profile waits at index 2, the active index became 2
// of 2 tabs and the tabs view failed an assertion. The waiting change kept
// the tab's index, and replaceAll left it as it was.
// Should: Profile shows. A change whose tab leaves the list is called off.
// What this holds to: the README, "Guarding tab routes": "The tab shows once
// its guards call resolver.next()". Native behavior: UIKit's
// UITabBarController follows the selected view controller, not its index,
// when its viewControllers change; Flutter's DefaultTabController keeps its
// index inside the new length.
void main() {
  setUp(() => _ordersGuardCalls = 0);

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a tab added before the tab whose guard decides does not '
      'show in its place',
      (tester) async {
        final routes = ValueNotifier<List<PageRouteInfo>>(const [
          NamedRoute('FeedTab'),
          NamedRoute('ProfileTab'),
        ]);
        addTearDown(routes.dispose);
        final router = _buildRouter(kind, routes);
        await pumpRouterApp(tester, router);
        // Made here, inside the test's fake clock, so pumping completes it.
        _profileDecision = Completer<bool>();
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        expect(tabs.current.name, 'FeedTab');

        // The user signs in: the tabs gain Orders before Profile.
        routes.value = const [
          NamedRoute('FeedTab'),
          NamedRoute('OrdersTab'),
          NamedRoute('ProfileTab'),
        ];
        await tester.pumpAndSettle();
        _profileDecision.complete(true);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          tabs.current.name,
          'ProfileTab',
          reason: 'the guard of OrdersTab was asked $_ordersGuardCalls times',
        );
        expect(find.text('ProfileTab'), findsOneWidget);
        expect(find.text('OrdersTab'), findsNothing);
      },
    );

    testWidgets(
      '${kind.name}: a tab removed before the tab whose guard decides leaves '
      'the active index inside the tabs',
      (tester) async {
        final routes = ValueNotifier<List<PageRouteInfo>>(const [
          NamedRoute('FeedTab'),
          NamedRoute('OrdersTab'),
          NamedRoute('ProfileTab'),
        ]);
        addTearDown(routes.dispose);
        final router = _buildRouter(kind, routes);
        await pumpRouterApp(tester, router);
        // Made here, inside the test's fake clock, so pumping completes it.
        _profileDecision = Completer<bool>();
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(2);
        await tester.pumpAndSettle();
        expect(tabs.current.name, 'FeedTab');

        routes.value = const [NamedRoute('FeedTab'), NamedRoute('ProfileTab')];
        await tester.pumpAndSettle();
        _profileDecision.complete(true);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(tabs.activeIndex, lessThan(tabs.pageCount));
        expect(tabs.current.name, 'ProfileTab');
        expect(find.text('ProfileTab'), findsOneWidget);
      },
    );

    testWidgets(
      '${kind.name}: a tab that leaves the list while its guard decides does '
      'not show',
      (tester) async {
        final routes = ValueNotifier<List<PageRouteInfo>>(const [
          NamedRoute('FeedTab'),
          NamedRoute('OrdersTab'),
          NamedRoute('ProfileTab'),
        ]);
        addTearDown(routes.dispose);
        final router = _buildRouter(kind, routes);
        await pumpRouterApp(tester, router);
        // Made here, inside the test's fake clock, so pumping completes it.
        _profileDecision = Completer<bool>();
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(2);
        await tester.pumpAndSettle();

        routes.value = const [NamedRoute('FeedTab'), NamedRoute('OrdersTab')];
        await tester.pumpAndSettle();
        _profileDecision.complete(true);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(tabs.activeIndex, 0);
        expect(find.text('FeedTab'), findsOneWidget);
        expect(_ordersGuardCalls, 0);
      },
    );
  }
}

enum _Tabs { indexedStack, pageView, tabBar }

// Completed with whether the guard of ProfileTab lets it in.
var _profileDecision = Completer<bool>();
var _ordersGuardCalls = 0;

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
        NamedRouteDef(
          name: 'FeedTab',
          path: 'feed',
          builder: (_, _) => const Center(child: Text('FeedTab')),
        ),
        NamedRouteDef(
          name: 'OrdersTab',
          path: 'orders',
          guards: [
            AutoRouteGuard.simple((resolver, _) {
              _ordersGuardCalls++;
              resolver.reject();
            }),
          ],
          builder: (_, _) => const Center(child: Text('OrdersTab')),
        ),
        NamedRouteDef(
          name: 'ProfileTab',
          path: 'profile',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              if (await _profileDecision.future) {
                resolver.next();
              } else {
                resolver.reject();
              }
            }),
          ],
          builder: (_, _) => const Center(child: Text('ProfileTab')),
        ),
      ],
    ),
  ],
);
