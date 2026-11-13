import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// When the tabs list changes while the view still moves to the tab chosen,
// the view rests on the tab the router names.
// Steps: the tabs FeedTab, ProfileTab and SettingsTab. Choose a tab, as a tap
// in a bottom bar does, and 100 ms later, while the view still moves, rebuild
// the tabs with another list, as a sign-in or a feature flag does that adds
// or removes a tab.
// Was: AutoTabsRouter.tabBar rested on another tab's page, often a blank
// one, while the router and the tab bar named the tab chosen. On the new tab
// controller the view only corrected its pixels, and the move still running
// went on to the page of the old list. AutoTabsRouter.pageView is a control.
// Native behavior this holds to: Flutter's TabBarView jumps to the new
// controller's index when it is given one, and a jump ends the running
// animation.
void main() {
  for (final kind in _Tabs.values) {
    for (final (what, chosen, changed, shown) in _kCases) {
      testWidgets(
        '${kind.name}: $what while the view moves rests on $shown',
        (tester) => _expectRestsOn(tester, kind, chosen, changed, shown),
      );
    }
  }
}

Future<void> _expectRestsOn(
  WidgetTester tester,
  _Tabs kind,
  int chosen,
  List<String> changed,
  String shown,
) async {
  final routes = ValueNotifier<List<PageRouteInfo>>(_routesOf(_kStart));
  addTearDown(routes.dispose);
  final router = _buildRouter(kind, routes);
  await pumpRouterApp(tester, router);
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
    ..setActiveIndex(chosen);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  routes.value = _routesOf(changed);
  await tester.pumpAndSettle();

  expect((tabs.current.name, _onScreen().join(', ')), (shown, shown));
}

enum _Tabs { tabBar, pageView }

const _kStart = ['FeedTab', 'ProfileTab', 'SettingsTab'];

const _kNames = ['FeedTab', 'OrdersTab', 'ProfileTab', 'SettingsTab'];

// What changes, the tab chosen, the new tabs and the tab that then shows.
const _kCases = [
  (
    'the tab chosen two tabs away leaves the list',
    2,
    ['FeedTab', 'ProfileTab'],
    'FeedTab',
  ),
  (
    'a tab is added before the tab chosen two tabs away',
    2,
    ['FeedTab', 'OrdersTab', 'ProfileTab', 'SettingsTab'],
    'SettingsTab',
  ),
  (
    'a tab is added before the neighbor tab chosen',
    1,
    ['FeedTab', 'OrdersTab', 'ProfileTab', 'SettingsTab'],
    'ProfileTab',
  ),
  (
    'a tab is added in front of all',
    1,
    ['OrdersTab', 'FeedTab', 'ProfileTab', 'SettingsTab'],
    'ProfileTab',
  ),
  (
    'the neighbor tab chosen leaves the list',
    1,
    ['FeedTab', 'SettingsTab'],
    'FeedTab',
  ),
];

List<PageRouteInfo> _routesOf(List<String> names) => [
  for (final name in names) NamedRoute<Object?>(name),
];

// The tabs whose page can be tapped.
List<String> _onScreen() => [
  for (final name in _kNames)
    if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
];

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
          builder: (_, tabRoutes, _) => switch (kind) {
            .tabBar => AutoTabsRouter.tabBar(routes: tabRoutes),
            .pageView => AutoTabsRouter.pageView(routes: tabRoutes),
          },
        ),
      ),
      children: [
        for (final name in _kNames)
          NamedRouteDef(
            name: name,
            path: name.toLowerCase(),
            builder: (_, _) => Center(child: Text(name)),
          ),
      ],
    ),
  ],
);
