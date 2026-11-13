import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// When a change of the tabs list shows another tab, observers hear of it. It
// is a change from the tab that left when the tab shown was opened before,
// and its init when it opens now.
// Steps: the tabs FeedTab, OrdersTab and ProfileTab with an
// AutoRouterObserver and an AutoRouteObserver, each tab page an
// AutoRouteAware. Open ProfileTab, then rebuild the tabs with FeedTab and
// OrdersTab only. Once with every tab opened before, so FeedTab shows again.
// Once with homeIndex 1 and OrdersTab never opened, so it opens now.
// Was: no kind of tabs told its observers, and the page that showed again
// heard nothing. The page-view and tab-bar tabs never reported the init of a
// tab opened this way, and later reported its returns as changes. Each kind
// took the new active tab over without a report, and the tab that left had
// no index in the new list to name it.
// Native behavior this holds to: UIKit calls viewWillAppear on the view
// controller a UITabBarController selects when the selected one leaves its
// viewControllers. Flutter's Navigator pops a page that leaves its pages
// list, and RouteObserver then tells the page under it through didPopNext.
void main() {
  setUp(_events.clear);

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a tab opened before that shows when the tab on screen '
      'leaves the list is a change',
      (tester) => _expectEvents(tester, kind, homeIndex: -1),
    );
    testWidgets(
      '${kind.name}: a tab never opened that shows when the tab on screen '
      'leaves the list is an init, and a return to it a change',
      (tester) => _expectEvents(tester, kind, homeIndex: 1),
    );
  }
}

Future<void> _expectEvents(
  WidgetTester tester,
  _Tabs kind, {
  required int homeIndex,
}) async {
  final routes = ValueNotifier<List<PageRouteInfo>>([
    for (final name in _kTabNames) NamedRoute<Object?>(name),
  ]);
  addTearDown(routes.dispose);
  final router = _buildRouter(kind, routes, homeIndex);
  await pumpRouterApp(
    tester,
    router,
    observers: () => [_Observer(), AutoRouteObserver()],
  );
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  final visits = homeIndex == -1 ? [1, 2] : [2];
  for (final index in visits) {
    tabs.setActiveIndex(index);
    await tester.pumpAndSettle();
  }
  _events.clear();

  routes.value = const [
    NamedRoute<Object?>('FeedTab'),
    NamedRoute<Object?>('OrdersTab'),
  ];
  await tester.pumpAndSettle();
  final atListChange = List.of(_events);

  if (homeIndex == -1) {
    expect(atListChange, [
      'change FeedTab from ProfileTab',
      'FeedTab hears change from ProfileTab',
    ]);
    return;
  }
  // A tab that opened with the change is reported once: later returns are
  // changes.
  _events.clear();
  for (final index in [0, 1]) {
    tabs.setActiveIndex(index);
    await tester.pumpAndSettle();
  }
  expect(atListChange, [
    'init OrdersTab from ProfileTab',
    'OrdersTab hears init',
  ]);
  expect(_events, [
    'change FeedTab from OrdersTab',
    'FeedTab hears change from OrdersTab',
    'change OrdersTab from FeedTab',
    'OrdersTab hears change from FeedTab',
  ]);
}

enum _Tabs { indexedStack, pageView, tabBar, builder }

const _kTabNames = ['FeedTab', 'OrdersTab', 'ProfileTab'];

// The tab events heard, by the observer and by the pages, oldest first.
final _events = <String>[];

RootStackRouter _buildRouter(
  _Tabs kind,
  ValueNotifier<List<PageRouteInfo>> routes,
  int homeIndex,
) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => Scaffold(
        body: ValueListenableBuilder(
          valueListenable: routes,
          builder: (_, tabRoutes, _) => switch (kind) {
            .indexedStack => AutoTabsRouter(
              routes: tabRoutes,
              homeIndex: homeIndex,
            ),
            .pageView => AutoTabsRouter.pageView(
              routes: tabRoutes,
              homeIndex: homeIndex,
            ),
            .tabBar => AutoTabsRouter.tabBar(
              routes: tabRoutes,
              homeIndex: homeIndex,
            ),
            .builder => AutoTabsRouter.builder(
              routes: tabRoutes,
              homeIndex: homeIndex,
              builder: (_, children, tabs) =>
                  IndexedStack(index: tabs.activeIndex, children: children),
            ),
          },
        ),
      ),
      children: [
        for (final name in _kTabNames)
          NamedRouteDef(
            name: name,
            path: name.toLowerCase(),
            builder: (_, _) => _AwarePage(name),
          ),
      ],
    ),
  ],
);

class _Observer extends AutoRouterObserver {
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _events.add('init ${route.name} from ${previousRoute?.name ?? 'none'}');

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _events.add('change ${route.name} from ${previousRoute.name}');
}

class _AwarePage extends StatefulWidget {
  const new(this.name);

  final String name;

  @override
  State<_AwarePage> createState() => _AwarePageState();
}

class _AwarePageState extends State<_AwarePage>
    with AutoRouteAwareStateMixin<_AwarePage> {
  // The tab a page names as previous on its init comes from the tabs
  // router's previousIndex as the page subscribes, not from this report.
  @override
  void didInitTabRoute(TabPageRoute? previousRoute) =>
      _events.add('${widget.name} hears init');

  @override
  void didChangeTabRoute(TabPageRoute previousRoute) =>
      _events.add('${widget.name} hears change from ${previousRoute.name}');

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.name));
}
