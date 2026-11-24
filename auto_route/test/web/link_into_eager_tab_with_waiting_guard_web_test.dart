// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// In a real browser, an app opened at a link to a page in a tab whose guard
// waits, when the tabs build every tab at once, asks the page's guard once,
// after the tab guard lets the tab in. It opens the page once and keeps the
// one entry the browser made for the link. After a "no" of the tab guard,
// the tab holds no page of the link (callmephil/auto_route_library#45). The
// steps, what was seen and what should be seen are those of the headless
// test on the VM: test/link_into_eager_tab_with_waiting_guard_test.dart.
//
// Native behavior this holds to: Flutter's Navigator holds each page once,
// and a refused navigation leaves no page behind. The HTML standard's
// session history: the browser makes one entry for a url it opens.

// How the tabs page builds every tab at once, as in the headless test.
enum _Tabs { eager, builder, eagerPageView }

// The guards of Orders and Order note each ask, and the tab guard lets
// Orders in while [_isSignedIn].
final _asks = <String>[];
var _isSignedIn = true;

const _tabRoutes = [
  NamedRoute<Object?>('Shop'),
  NamedRoute<Object?>('Orders'),
  NamedRoute<Object?>('Account'),
];

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account, built as [tabs]
// says. Orders holds a nested router with OrdersIndex and Order.
RootStackRouter _storeRouter(_Tabs tabs) => .build(
  routes: [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => Scaffold(
        body: switch (tabs) {
          .eager => const AutoTabsRouter(lazyLoad: false, routes: _tabRoutes),
          .builder => AutoTabsRouter.builder(
            routes: _tabRoutes,
            builder: (_, children, tabsRouter) =>
                IndexedStack(index: tabsRouter.activeIndex, children: children),
          ),
          .eagerPageView => const AutoTabsRouter.pageView(
            routes: _tabRoutes,
            lazyLoad: false,
          ),
        },
      ),
      children: [
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              _asks.add('tab');
              await Future<void>.delayed(const Duration(milliseconds: 1));
              _asks.add('tab answers');
              _isSignedIn ? resolver.next() : resolver.reject();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndex', ''),
            NamedRouteDef(
              name: 'Order',
              path: ':id',
              guards: [
                AutoRouteGuard.simple((resolver, _) async {
                  _asks.add('order');
                  await Future<void>.delayed(const Duration(milliseconds: 1));
                  resolver.next();
                }),
              ],
              builder: (_, data) =>
                  Text('Order ${data.params.getString('id')}'),
            ),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ],
);

// The pages of the nested router of Orders, with the id of each Order.
String _orders(RootStackRouter router) {
  final pages =
      router
          .innerRouterOf<TabsRouter>('Store')
          ?.innerRouterOf<StackRouter>('Orders')
          ?.stack ??
      const <AutoRoutePage<Object?>>[];
  return pages
      .map(
        (page) => [
          page.routeData.name,
          ?page.routeData.params.optString('id'),
        ].join(' '),
      )
      .join(', ');
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  setUp(() {
    _asks.clear();
    _isSignedIn = true;
  });

  // Opens the app at /store/orders/7 the way a browser does. Answers the
  // router and the serial count of the link's entry.
  Future<(RootStackRouter, int)> open(WidgetTester tester, _Tabs tabs) async {
    final router = _storeRouter(tabs);
    addTearDown(router.dispose);
    final first = browserSerialCount < 0 ? 0 : browserSerialCount;
    openBrowserAt(tester, '/store/orders/7');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(routerConfig: router.config()),
    );
    await settleBrowser(tester);
    return (router, first);
  }

  for (final tabs in _Tabs.values) {
    testWidgets('Opened at /store/orders/7 with the ${tabs.name} tabs: the '
        'guard of Order is asked once, after the tab guard, Order 7 opens '
        'once, and the link keeps one entry', (tester) async {
      final (router, first) = await open(tester, tabs);

      expect(
        (
          _asks.join(', '),
          _orders(router),
          browserSerialCount - first,
          browserPath,
        ),
        ('tab, tab answers, order', 'Order 7', 0, '/store/orders/7'),
      );
    });

    testWidgets('Opened at /store/orders/7 with the ${tabs.name} tabs, the '
        'tab guard says no: Orders holds no page of the link, and a later '
        'change to the tab shows OrdersIndex', (tester) async {
      _isSignedIn = false;
      final (router, _) = await open(tester, tabs);
      expect((_orders(router), browserPath), ('OrdersIndex', '/store/shop'));

      _isSignedIn = true;
      router.innerRouterOf<TabsRouter>('Store')!.setActiveIndex(1);
      await settleBrowser(tester);

      expect(
        (router.topRoute.name, browserPath, _asks.contains('order')),
        ('OrdersIndex', '/store/orders', false),
      );
    });
  }
}
