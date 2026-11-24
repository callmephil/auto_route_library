import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// A link to a page in a tab whose guard waits opens the page once, after
// that guard lets the tab in, also when the tabs build every tab at once.
// Before, the nested router of the tab, built with the tabs, opened the page
// while the tab guard decided, and the tab change opened it again. After a
// "no" of the tab guard the page stayed in the tab, and after a "no" inside
// the tab the tabs page stayed open (callmephil/auto_route_library#45).
// Headless tests:
// auto_route/test/link_into_eager_tab_with_waiting_guard_test.dart and
// auto_route/test/web/link_into_eager_tab_with_waiting_guard_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator holds each page once.
// Android's conditional navigation goes back from a destination whose check
// fails, and a refused navigation leaves no page behind. On the web, the
// HTML standard's session history: the browser makes one entry for a url it
// opens.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a link into a tab whose guard waits, with every tab built', () {
    setUp(() {
      _asks.clear();
      _isSignedIn = true;
      _allowsIndex = true;
    });

    for (final tabs in _tabsKinds) {
      // Steps: open the app at /store/orders/7. The guard of the tab Orders
      // waits 1 ms, and so does the guard of Order.
      // Was: the guard of Order was asked before the tab guard answered and
      // again after it, and Order 7 was on the stack of Orders two times.
      // Should: the guard of Order is asked once, after the tab guard, and
      // Order 7 opens once, on the one entry of the link.
      testWidgets(
        'Opened at /store/orders/7: Order 7 opens once, after the tab guard, '
        'with the ${tabs.name}',
        (tester) async {
          final router = _storeRouter(tabs);
          final linkEntry = await _openAtLink(tester, router);

          expect(
            (_asks.join(', '), _orders(router)),
            ('tab, tab answers, order', 'OrderRoute 7'),
          );
          expect(find.text('Order 7'), findsOneWidget);
          await expectBrowserUrl('/store/orders/7');
          await expectAppWroteDeepLinkEntry(linkEntry);
        },
      );

      // Steps: on Home, call navigatePath to /store/orders/7, then go back.
      // Was: back showed Order 7 again.
      // Should: back shows Home.
      testWidgets(
        'navigatePath from Home: Order 7 opens once, and back shows Home, '
        'with the ${tabs.name}',
        (tester) async {
          final router = _storeRouter(tabs);
          await pumpRouterAppWithConfig(tester, router);

          unawaited(router.navigatePath('/store/orders/7'));
          await tester.pumpAndSettle();
          expect(
            (_asks.join(', '), _orders(router)),
            ('tab, tab answers, order', 'OrderRoute 7'),
          );

          await _expectBack(tester, router, ('HomeRoute', '/'));
        },
      );

      // Steps: open the app at /store/orders/7 while the tab guard says no.
      // Then let the guard say yes, and select the tab Orders.
      // Was: Order 7 stayed in Orders, and the tab change showed it.
      // Should: Orders holds no page of the link, and shows OrdersIndex.
      testWidgets(
        'Opened at /store/orders/7, the tab guard says no: Orders holds no '
        'page of the link, with the ${tabs.name}',
        (tester) async {
          _isSignedIn = false;
          final router = _storeRouter(tabs);
          await _openAtLink(tester, router);
          expect(
            (router.topRoute.name, _orders(router)),
            ('ShopTab', 'OrdersIndexRoute'),
          );
          await expectBrowserUrl('/store/shop');

          _isSignedIn = true;
          router.innerRouterOf<TabsRouter>('StoreRoute')!.setActiveIndex(1);
          await tester.pumpAndSettle();

          expect(
            (router.topRoute.name, _asks.contains('order')),
            ('OrdersIndexRoute', false),
          );
          await expectBrowserUrl('/store/orders');
        },
      );

      // Steps: on Home, push the path /store/orders. The guard of
      // OrdersIndex says no.
      // Was: the tabs page stayed open on Shop, and onFailure heard nothing.
      // Should: Home stays, and onFailure hears the no once.
      testWidgets(
        'pushPath to Orders, a guard inside the tab says no: Home stays, '
        'with the ${tabs.name}',
        (tester) async {
          _allowsIndex = false;
          final router = _storeRouter(tabs);
          await pumpRouterAppWithConfig(tester, router);

          final failures = <NavigationFailure>[];
          unawaited(
            router.pushPath<Object?>('/store/orders', onFailure: failures.add),
          );
          await tester.pumpAndSettle();

          expect(
            (router.topRoute.name, router.stack.length, failures.length),
            ('HomeRoute', 1, 1),
          );
          expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
          await expectBrowserUrl('/');
        },
      );
    }
  });
}

// Goes back one step, with the browser's back button on the web and with
// the app's own back() off it, and expects [page], a name and a url.
Future<void> _expectBack(
  WidgetTester tester,
  RootStackRouter router,
  (String, String) page,
) async {
  if (kIsWeb) {
    await expectBrowserBackWalk(tester, router, [page]);
    return;
  }
  router.back();
  await tester.pumpAndSettle();
  final (name, url) = page;
  expect((router.topRoute.name, router.currentUrl), (name, url));
}

// The guards of Orders, OrdersIndex and Order note each ask. The tab guard
// lets Orders in while [_isSignedIn], and the guard of OrdersIndex lets the
// page in while [_allowsIndex].
final _asks = <String>[];
var _isSignedIn = true;
var _allowsIndex = true;

const _kTabRoutes = [
  NamedRoute<Object?>('ShopTab'),
  NamedRoute<Object?>('OrdersTab'),
  NamedRoute<Object?>('AccountTab'),
];

// A way the tabs page builds every tab at once, by its [name].
typedef _TabsKind = ({String name, Widget Function() page});

final List<_TabsKind> _tabsKinds = [
  (
    name: 'tabs with lazyLoad false',
    page: () => const AutoTabsRouter(lazyLoad: false, routes: _kTabRoutes),
  ),
  (
    name: 'builder of AutoTabsRouter',
    page: () => AutoTabsRouter.builder(
      routes: _kTabRoutes,
      builder: (_, children, tabsRouter) =>
          IndexedStack(index: tabsRouter.activeIndex, children: children),
    ),
  ),
  (
    name: 'page view that loads every tab',
    page: () =>
        const AutoTabsRouter.pageView(routes: _kTabRoutes, lazyLoad: false),
  ),
];

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account, built as [tabs]
// says. Orders holds a nested router with OrdersIndex and Order.
RootStackRouter _storeRouter(_TabsKind tabs) => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'StoreRoute',
      path: '/store',
      builder: (_, _) => Scaffold(body: tabs.page()),
      children: [
        _page('ShopTab', 'shop'),
        NamedRouteDef(
          name: 'OrdersTab',
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
            NamedRouteDef(
              name: 'OrdersIndexRoute',
              path: '',
              guards: [
                AutoRouteGuard.simple((resolver, _) {
                  _asks.add('index');
                  _allowsIndex ? resolver.next() : resolver.reject();
                }),
              ],
              builder: (_, _) => const Text('OrdersIndexRoute'),
            ),
            NamedRouteDef(
              name: 'OrderRoute',
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
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);

// Opens the app of [router] at /store/orders/7 as the platform opens it,
// with the link's page alone, as on the web. Answers the browser entry of
// the link.
Future<int> _openAtLink(WidgetTester tester, RootStackRouter router) async {
  final linkEntry = browserEntryIndex() ?? 0;
  // The config reads the platform's initial route when it is first made, so
  // it is made inside the app, after pumpAppAtDeepLink sets the link, as
  // runApp would find it.
  await pumpAppAtDeepLink(
    tester,
    '/store/orders/7',
    Builder(
      builder: (_) => MaterialApp.router(
        routerConfig: router.config(includePrefixMatches: false),
      ),
    ),
  );
  return linkEntry;
}

// The pages of the nested router of the tab Orders of [router], with the id
// of each Order.
String _orders(RootStackRouter router) {
  final pages =
      router
          .innerRouterOf<TabsRouter>('StoreRoute')
          ?.innerRouterOf<StackRouter>('OrdersTab')
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
