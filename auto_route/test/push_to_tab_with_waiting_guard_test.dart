import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// A navigation to a tab whose guard waits gives the tabs page one entry,
// also when the tabs build the tab's nested router before the tab shows
// (callmephil/auto_route_library#34).
//
// Steps: on Home, push the path /store/orders. Store opens on its Shop tab
// while the guard of the Orders tab waits 1 ms, then lets the tab in.
// The tabs build the nested router of Orders before the tab shows: with
// AutoTabsRouter.builder, which builds every tab at once, with a page view
// that loads every tab at once, or off the screen, to ask a guard of the
// app there. Press the browser's back button, then its forward button.
// Was: the browser held /, /store/shop and /store/orders, and back showed
// Shop, a page the user did not open. Once the guard lets the tab in, the
// tabs mark the url for a replace, so that the tab takes the place of Shop.
// But the nested router of Orders then opened its first page off the
// screen, and its url report, which still named Shop, used the mark up.
// The url of Orders then made an entry of its own. Off the web, back()
// showed Shop too. And when a guard in the nested router of Orders said no,
// the tab never showed and the mark stayed: the user's next tab change, to
// Account, took the place of the entry of Shop, and back from Account
// skipped Shop.
// Should: the url of Orders takes the place of the url of Shop. Back shows
// Home, and forward shows Orders again on the same entry. After a no inside
// the tab, the tab change to Account adds an entry of its own, and back
// shows Shop again. With the guard of the app, the tab shows at once and
// the no inside it takes the new tabs page back
// (callmephil/auto_route_library#33), so no tab change follows.
//
// Native behavior this holds to: one navigation adds one step back, as
// each call of Android's NavController.navigate pushes one destination and
// Flutter's Navigator.push one route. The tab that the guard lets in takes
// the place of the tab shown meanwhile, as Navigator.pushReplacement puts
// a route in the place of the route on top, and as history.replaceState
// writes over the current entry of the browser (HTML standard).
//
// The same steps run in a real browser in
// test/web/push_to_tab_with_waiting_guard_web_test.dart, and in the example
// app in example.old/integration_test/push_to_tab_with_waiting_guard_test.dart.

// How the tabs page builds its tabs. Each way builds the nested router of
// Orders before the tab shows.
enum _Tabs {
  // AutoTabsRouter.builder, which shows every tab in an IndexedStack.
  builder,
  // AutoTabsRouter.pageView, which loads every tab at once.
  eagerPageView,
  // The default AutoTabsRouter, with a guard of the app that lets every page
  // in: the tab's nested router is built off the screen to ask it.
  appGuard,
}

// Home, then Store with the tabs Shop, Orders and Account, built as [tabs]
// says. Orders has a guard that waits 1 ms, then lets the tab in, and a
// nested router with OrdersIndex, whose guard says no with [refusesIndex].
// With a [_browser], the router writes it; without one, the history is the
// app's own one off the web.
class _StoreRouter extends RootStackRouter {
  new(this._browser, {required this.tabs, required this.refusesIndex});

  final TestHistoryBrowser? _browser;
  final _Tabs tabs;
  final bool refusesIndex;

  @override
  late final NavigationHistory navigationHistory = switch (_browser) {
    final browser? => BrowserNavigationHistory(
      this,
      browser,
      // The test's clock runs through every animation at once; the browser
      // of a test lands late, never too late.
      landingLimit: const Duration(hours: 1),
    ),
    null => super.navigationHistory,
  };

  @override
  late final List<AutoRouteGuard> guards = [
    if (tabs == .appGuard)
      AutoRouteGuard.simple((resolver, _) => resolver.next()),
  ];

  static const _tabRoutes = [
    NamedRoute<Object?>('Shop'),
    NamedRoute<Object?>('Orders'),
    NamedRoute<Object?>('Account'),
  ];

  Widget _tabsPage() => switch (tabs) {
    .builder => AutoTabsRouter.builder(
      routes: _tabRoutes,
      builder: (_, children, tabsRouter) =>
          IndexedStack(index: tabsRouter.activeIndex, children: children),
    ),
    .eagerPageView => const AutoTabsRouter.pageView(
      routes: _tabRoutes,
      lazyLoad: false,
    ),
    .appGuard => const AutoTabsRouter(routes: _tabRoutes),
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
            // A sign-in check that waits, as for a token in storage.
            AutoRouteGuard.simple((resolver, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'OrdersIndex',
              path: '',
              guards: [
                // A check of the page's own, such as for a feature flag.
                if (refusesIndex)
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
              ],
              builder: (_, _) => const Text('OrdersIndex'),
            ),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

// The app of a test, on Home, then on Store after pushPath('/store/orders').
class _App {
  new(
    this.tester, {
    required _Tabs tabs,
    bool refusesIndex = false,
    bool writesBrowser = true,
  }) {
    router = _StoreRouter(
      writesBrowser ? browser : null,
      tabs: tabs,
      refusesIndex: refusesIndex,
    );
    if (writesBrowser) {
      addTearDown(router.navigationHistory.dispose);
      browser.reportLandingsTo(tester);
    }
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // The page on top and the url of the app, off the web.
  String get shownByApp => '${router.topRoute.name} ${router.currentUrl}';

  Future<void> openOrders() async {
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
    unawaited(router.pushPath<Object?>('/store/orders'));
    await browser.settle(tester);
  }

  // The user selects the Account tab.
  Future<void> selectAccount() async {
    router.innerRouterOf<TabsRouter>('Store')!.setActiveIndex(2);
    await browser.settle(tester);
  }

  // The page shown after each press of [press], at most [limit] presses,
  // until it has no entry to go to.
  Future<List<String>> walk(bool Function() press, int limit) async {
    final shownAfter = <String>[];
    for (var i = 0; i < limit && press(); i++) {
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }

  // The page shown after each back() of the app's own history off the web,
  // until it has no entry to go back to.
  Future<List<String>> walkBack() async {
    final shownAfter = <String>[];
    for (var i = 0; i < 4 && router.navigationHistory.canNavigateBack; i++) {
      router.back();
      await tester.pumpAndSettle();
      shownAfter.add(shownByApp);
    }
    return shownAfter;
  }
}

void main() {
  for (final tabs in _Tabs.values) {
    group('With tabs that build Orders before it shows (${tabs.name})', () {
      testWidgets('pushPath to Orders gives Store one entry, and back and '
          'forward walk Home and Orders', (tester) async {
        final app = _App(tester, tabs: tabs);
        await app.openOrders();
        expect(app.shown, 'OrdersIndex /store/orders');
        // Read before the walk: the entries the browser holds on Orders.
        final heldOnOrders = app.browser.held;
        final asked = app.browser.asked.length;

        expect(await app.walk(app.browser.didPressBack, 3), ['Home /']);
        expect(await app.walk(app.browser.didPressForward, 3), [
          'OrdersIndex /store/orders',
        ]);
        const onOrders = '/ >/store/orders';
        expect((heldOnOrders, app.browser.held), (onOrders, onOrders));
        // No new entry and no step. Forward opens Store again, on Shop while
        // the guard of Orders decides, and the entry names the tab on
        // screen until Orders is let in, as when the app first opened it.
        expect(
          app.browser.asked
              .skip(asked)
              .where((call) => !call.startsWith('replace ')),
          isEmpty,
        );
      });

      testWidgets('off the web, back() after pushPath to Orders shows Home', (
        tester,
      ) async {
        final app = _App(tester, tabs: tabs, writesBrowser: false);
        await app.openOrders();
        expect(app.shownByApp, 'OrdersIndex /store/orders');

        expect(await app.walkBack(), ['Home /']);
      }, skip: kIsWeb);

      // Tabs that build Orders at once keep Shop after a no inside Orders,
      // as the tab never showed. With the guard of the app, the no takes
      // Store back: see the test after this group.
      if (tabs == .appGuard) return;

      testWidgets('after a no of the guard inside Orders, a change to the '
          'Account tab adds an entry, and back shows Shop again', (
        tester,
      ) async {
        final app = _App(tester, tabs: tabs, refusesIndex: true);
        await app.openOrders();
        // The no keeps the tabs page, on Shop.
        expect(app.shown, 'Shop /store/shop');
        final asked = app.browser.asked.length;

        await app.selectAccount();

        expect(app.browser.asked.skip(asked), ['push /store/account']);
        expect(app.browser.held, '/ /store/shop >/store/account');
        expect(await app.walk(app.browser.didPressBack, 1), [
          'Shop /store/shop',
        ]);
      });

      testWidgets('off the web, after a no of the guard inside Orders, back() '
          'from the Account tab shows Shop', (tester) async {
        final app = _App(
          tester,
          tabs: tabs,
          refusesIndex: true,
          writesBrowser: false,
        );
        await app.openOrders();
        expect(app.shownByApp, 'Shop /store/shop');
        await app.selectAccount();

        expect(await app.walkBack(), ['Shop /store/shop', 'Home /']);
      }, skip: kIsWeb);
    });
  }

  // With the guard of the app, the tab that the path names shows as soon as
  // its own guard lets it in, and its nested router asks the guard of
  // OrdersIndex on screen: the no then takes the new tabs page back, as a
  // nested guard's no does (callmephil/auto_route_library#33).
  for (final writesBrowser in [true, if (!kIsWeb) false]) {
    testWidgets('With the guard of the app, a no of the guard inside Orders '
        'takes Store back${writesBrowser ? '' : ', off the web'}', (
      tester,
    ) async {
      final app = _App(
        tester,
        tabs: .appGuard,
        refusesIndex: true,
        writesBrowser: writesBrowser,
      );
      await app.openOrders();

      expect(
        (
          writesBrowser ? app.shown : app.shownByApp,
          app.router.stack.map((page) => page.name).join(' '),
        ),
        ('Home /', 'Home'),
      );
    });
  }
}
