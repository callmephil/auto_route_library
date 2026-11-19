// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// In a real browser, an app opened at a link to a page in a tab whose guard
// waits, when that page has a guard of its own, opens the page once, asks
// its guard once and keeps the one entry the browser made for the link
// (callmephil/auto_route_library#33). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/link_to_guarded_page_in_waiting_tab_test.dart.
//
// Native behavior this holds to: Flutter's Navigator holds each page once.
// The HTML standard's session history: the browser makes one entry for a
// url it opens.

// How many times the guard of Order was asked, and whether it lets the page
// in.
var _orderAsks = 0;
var _allowsOrder = true;

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account. Orders holds a
// nested router and a guard that waits 1 ms, then lets the tab in. Order
// has a guard of its own, which waits 1 ms when [orderWaits] and answers at
// once otherwise.
RootStackRouter _storeRouter({required bool orderWaits}) => .build(
  routes: [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('Shop'),
            NamedRoute<Object?>('Orders'),
            NamedRoute<Object?>('Account'),
          ],
        ),
      ),
      children: [
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          guards: [
            // A sign-in check that waits, as for a token in storage.
            AutoRouteGuard.simple((resolver, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndex', ''),
            NamedRouteDef(
              name: 'Order',
              path: ':id',
              guards: [
                // A check of the order's own, such as for its owner.
                AutoRouteGuard.simple((resolver, _) async {
                  _orderAsks++;
                  if (orderWaits) {
                    await Future<void>.delayed(const Duration(milliseconds: 1));
                  }
                  if (_allowsOrder) {
                    resolver.next();
                  } else {
                    resolver.reject();
                  }
                }),
              ],
              builder: (_, _) => const Text('Order'),
            ),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  setUp(() {
    _orderAsks = 0;
    _allowsOrder = true;
  });

  // Opens the app at /store/orders/7 the way a browser does, and returns a
  // reading of the pages in Orders, the page on top, the entry counted from
  // the link's, and the url.
  Future<String Function()> open(
    WidgetTester tester, {
    required bool orderWaits,
  }) async {
    final router = _storeRouter(orderWaits: orderWaits);
    addTearDown(router.dispose);
    final first = browserSerialCount < 0 ? 0 : browserSerialCount;
    openBrowserAt(tester, '/store/orders/7');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(routerConfig: router.config()),
    );
    await settleBrowser(tester);
    return () {
      final orders = router
          .innerRouterOf<TabsRouter>('Store')
          ?.innerRouterOf<StackRouter>('Orders');
      final pages = orders?.stack.map((page) => page.routeData.name) ?? [];
      return '${pages.join(', ')}; ${router.topRoute.name} '
          '${browserSerialCount - first} $browserPath';
    };
  }

  for (final orderWaits in [true, false]) {
    testWidgets('Opened at /store/orders/7: Order 7 opens once, its guard is '
        'asked once, and the link keeps one entry'
        '${orderWaits ? ', with a guard of Order that waits' : ''}', (
      tester,
    ) async {
      final reading = await open(tester, orderWaits: orderWaits);

      expect((reading(), _orderAsks), ('Order; Order 0 /store/orders/7', 1));
    });
  }

  testWidgets('Opened at /store/orders/7, the guard of Order says no: the '
      'tab Orders shows its first page, on the one entry of the link', (
    tester,
  ) async {
    _allowsOrder = false;
    final reading = await open(tester, orderWaits: true);

    expect(
      (reading(), _orderAsks),
      ('OrdersIndex; OrdersIndex 0 /store/orders', 1),
    );
  });
}
