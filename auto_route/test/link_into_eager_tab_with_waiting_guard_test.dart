import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// A link to a page in a tab whose guard waits opens the page once, after
// that guard lets the tab in, also when the tabs build every tab at once
// (callmephil/auto_route_library#45).
//
// Steps: the tabs page Store is not open. It builds every tab at once with
// AutoTabsRouter(lazyLoad: false), AutoTabsRouter.builder or
// AutoTabsRouter.pageView(lazyLoad: false), or each tab as it shows. The
// guard of its tab Orders waits 1 ms, as a sign-in check that reads a token.
// Order, in the nested router of Orders, has a guard that waits 1 ms. Open
// the app at /store/orders/7, or on Home call navigatePath to it.
// Was: the nested router of Orders, built with the tabs, opened Order 7
// while the tab guard decided, so the guard of Order was asked before the
// tab guard answered. After the yes, the tab change opened Order 7 again.
// The stack of Orders held it two times, and back showed it again. After a
// "no" of the tab guard, Order 7 stayed in Orders with any tabs, and a later
// change to the tab showed it. So it did when the user chose another tab
// while the tab guard decided. With a guard of OrdersIndex that says no, a
// push of /store/orders left Store open on Shop, and onFailure heard nothing.
// Should: the result of the default tabs. The guard of Order is asked
// once, after the tab guard says yes, and Order 7 opens once. After a "no"
// of the tab guard, or another tab chosen meanwhile, Orders holds no page of
// the link, and a later change to the tab shows OrdersIndex. A "no" inside
// the tab takes Store back, and onFailure hears it. On the web the link
// keeps its one entry.
//
// Native behavior this holds to: Flutter's Navigator holds each page once.
// Android's conditional navigation goes back from a destination whose check
// fails. UITabBarController keeps its tab when
// tabBarController(_:shouldSelect:) returns false, and a refused navigation
// leaves no page behind. In the HTML standard's session history, the browser
// makes one entry for a url it opens.
//
// The same steps run in a real browser in
// test/web/link_into_eager_tab_with_waiting_guard_web_test.dart, and in the
// example app in
// example.old/integration_test/link_into_eager_tab_with_waiting_guard_test.dart.

// How the tabs page builds its tabs: every tab at once, in three ways, or
// each tab once it shows, as the default tabs do.
enum _Tabs { eager, builder, eagerPageView, lazy }

// Home, then Store with the tabs Shop, Orders and Account, built as [tabs]
// says. The guards of Orders, OrdersIndex and Order note each ask in [asks].
class _StoreRouter extends RootStackRouter {
  new(this._browser, {required this.tabs});

  final TestHistoryBrowser? _browser;
  final _Tabs tabs;

  bool isSignedIn = true;
  bool allowsIndex = true;
  final asks = <String>[];

  @override
  late final NavigationHistory navigationHistory = switch (_browser) {
    null => super.navigationHistory,
    final browser => BrowserNavigationHistory(
      this,
      browser,
      // The test's clock runs through every animation at once; the browser
      // of a test lands late, never too late.
      landingLimit: const Duration(hours: 1),
    ),
  };

  static const _tabRoutes = [
    NamedRoute<Object?>('Shop'),
    NamedRoute<Object?>('Orders'),
    NamedRoute<Object?>('Account'),
  ];

  Widget _tabsPage() => switch (tabs) {
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
    .lazy => const AutoTabsRouter(routes: _tabRoutes),
  };

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => Scaffold(body: _tabsPage()),
      children: [
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              asks.add('tab');
              await Future<void>.delayed(const Duration(milliseconds: 1));
              asks.add('tab answers');
              isSignedIn ? resolver.next() : resolver.reject();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'OrdersIndex',
              path: '',
              guards: [
                AutoRouteGuard.simple((resolver, _) {
                  asks.add('index');
                  allowsIndex ? resolver.next() : resolver.reject();
                }),
              ],
              builder: (_, _) => const Text('OrdersIndex'),
            ),
            NamedRouteDef(
              name: 'Order',
              path: ':id',
              guards: [
                AutoRouteGuard.simple((resolver, _) async {
                  asks.add('order');
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
  ];
}

// The app of a test: on the web, opened at [launchAt] as a browser opens it,
// with one browser entry; off the web, on Home.
class _App {
  new(
    this.tester, {
    required this.isOnWeb,
    required _Tabs tabs,
    String? launchAt,
  }) {
    if (launchAt != null) {
      browser.entries
        ..clear()
        ..add((launchAt, null));
      final dispatcher = tester.binding.platformDispatcher
        ..defaultRouteNameTestValue = launchAt;
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    }
    router = _StoreRouter(isOnWeb ? browser : null, tabs: tabs);
    if (isOnWeb) browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final bool isOnWeb;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  String get shown => '${router.topRoute.name} ${router.currentUrl}';

  String get asks => router.asks.join(', ');

  String get stack =>
      router.stack.map((page) => page.routeData.name).join(', ');

  TabsRouter get tabs => router.innerRouterOf('Store')!;

  // The pages of the nested router of Orders, with the id of each Order.
  String get orders {
    final pages =
        tabs.innerRouterOf<StackRouter>('Orders')?.stack ??
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

  // What the app asked of the browser other than to write over the entry
  // it stands on: a new entry or a step.
  Iterable<String> get pushesAndSteps =>
      browser.asked.where((call) => !call.startsWith('replace '));

  Future<void> open() async {
    // Off the web the router disposes its own history.
    if (isOnWeb) addTearDown(router.navigationHistory.dispose);
    // As on the web, where a link brings its own page alone.
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );
    await settle();
  }

  Future<void> settle() =>
      isOnWeb ? browser.settle(tester) : tester.pumpAndSettle();
}

void main() {
  for (final tabs in _Tabs.values) {
    group('With the ${tabs.name} tabs', () {
      testWidgets('on the web, opened at /store/orders/7: the guard of Order '
          'is asked once, after the tab guard, Order 7 opens once, and the '
          'link keeps one entry', (tester) async {
        final app = _App(
          tester,
          isOnWeb: true,
          tabs: tabs,
          launchAt: '/store/orders/7',
        );
        await app.open();

        expect(
          (app.asks, app.shown, app.orders, app.browser.held),
          (
            'tab, tab answers, order',
            'Order /store/orders/7',
            'Order 7',
            '>/store/orders/7',
          ),
        );
        expect(app.pushesAndSteps, isEmpty);
      });

      testWidgets('off the web, navigatePath from Home: the guard of Order is '
          'asked once, after the tab guard, and one back shows Home', (
        tester,
      ) async {
        final app = _App(tester, isOnWeb: false, tabs: tabs);
        await app.open();

        unawaited(app.router.navigatePath('/store/orders/7'));
        await app.settle();
        expect(
          (app.asks, app.shown, app.orders),
          ('tab, tab answers, order', 'Order /store/orders/7', 'Order 7'),
        );

        await tester.binding.handlePopRoute();
        await app.settle();
        expect((app.shown, app.stack), ('Home /', 'Home'));
      });

      testWidgets('on the web, opened at /store/orders/7, the tab guard says '
          'no: Orders holds no page of the link, and a later change to the '
          'tab shows OrdersIndex', (tester) async {
        final app = _App(
          tester,
          isOnWeb: true,
          tabs: tabs,
          launchAt: '/store/orders/7',
        );
        app.router.isSignedIn = false;
        await app.open();
        // Tabs built at once open the first page of Orders.
        expect(
          (app.shown, app.orders),
          ('Shop /store/shop', tabs == .lazy ? '' : 'OrdersIndex'),
        );

        app.router.isSignedIn = true;
        app.tabs.setActiveIndex(1);
        await app.settle();

        expect(
          (app.shown, app.orders, app.router.asks.contains('order')),
          ('OrdersIndex /store/orders', 'OrdersIndex', false),
        );
      });

      testWidgets('off the web, the user chooses Account while the tab guard '
          'decides: Orders holds no page of the link, and a later change to '
          'the tab shows OrdersIndex', (tester) async {
        final app = _App(tester, isOnWeb: false, tabs: tabs);
        await app.open();

        unawaited(app.router.navigatePath('/store/orders/7'));
        // Store builds its tabs, and the tab guard waits.
        await tester.pump();
        await tester.pump();
        app.tabs.setActiveIndex(2);
        await app.settle();
        expect(
          (app.shown, app.orders),
          ('Account /store/account', tabs == .lazy ? '' : 'OrdersIndex'),
        );

        app.tabs.setActiveIndex(1);
        await app.settle();

        expect(
          (app.shown, app.orders, app.router.asks.contains('order')),
          ('OrdersIndex /store/orders', 'OrdersIndex', false),
        );
      });

      testWidgets('off the web, pushPath to Orders with a guard of OrdersIndex '
          'that says no: Store is taken back, and onFailure hears the no', (
        tester,
      ) async {
        final app = _App(tester, isOnWeb: false, tabs: tabs);
        await app.open();
        app.router.allowsIndex = false;

        final failures = <NavigationFailure>[];
        unawaited(
          app.router.pushPath<Object?>(
            '/store/orders',
            onFailure: failures.add,
          ),
        );
        await app.settle();

        expect(
          (app.shown, app.stack, app.asks),
          ('Home /', 'Home', 'tab, tab answers, index'),
        );
        expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      });
    });
  }
}
