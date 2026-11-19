import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// A link to a page in a tab whose guard waits, when that page has a guard
// of its own, opens the page once and asks its guard once. On the web the
// link keeps the one browser entry the browser made for it
// (callmephil/auto_route_library#33).
//
// Steps: the tabs page Store is not open. The guard of its tab Orders waits
// 1 ms, as a sign-in check that reads a token. Order, in the nested router
// of Orders, has a guard of its own that waits 1 ms or answers at once.
// Open the app at /store/orders/7, or on Home call navigatePath to it.
// Was: the tabs showed Shop while the tab guard decided. Then the Orders
// tab was built off the screen from its page, which still held Order 7:
// its router opened Order 7, and the tab change opened Order 7 again. The
// guard of Order was asked two times. With a guard that waits, Order 7 was
// on the stack two times: back showed it again, and on the web the next
// back failed the assertion of Flutter's Navigator on two pages with one
// key. On the web the link got a second entry, for the url of Order 7.
// After a "no" of the guard of Order, Shop stayed on screen, and from Home
// the tabs page stayed and onFailure heard nothing.
// Should: the same result as with a tab guard that answers at once. The
// tab shows with Order 7, which opens once, and its guard is asked once.
// The link keeps one entry. After a "no", the tab shows its first page
// at launch, and navigatePath from Home leaves Home, and onFailure hears
// the rejection.
//
// Native behavior this holds to: Flutter's Navigator holds each page once,
// and asserts when two pages have one key. Android's conditional navigation
// pops back from a destination whose check fails. On the web, the HTML
// standard's session history: the browser makes one entry for a url it
// opens.
//
// The same steps run in a real browser in
// test/web/link_to_guarded_page_in_waiting_tab_web_test.dart, and in the
// example app in
// example.old/integration_test/link_to_guarded_page_in_waiting_tab_test.dart.

// The app of the issue: Home, then Store with the tabs Shop, Orders and
// Account. Orders holds a nested router with OrdersIndex and Order, and a
// guard that waits 1 ms, then lets the tab in. Order has a guard of its own
// that waits [orderGuardWait] when it is more than zero, then lets the page
// in while [allowsOrder] says so. It counts its asks in [orderAsks]. On the
// web the history writes [_browser]; off the web it is the app's own.
class _StoreRouter extends RootStackRouter {
  new(this._browser, {required this.orderGuardWait});

  final TestHistoryBrowser? _browser;
  final Duration orderGuardWait;

  // Whether the guard of Order lets the page in.
  bool allowsOrder = true;

  // How many times the guard of Order was asked.
  int orderAsks = 0;

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

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
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
                  orderAsks++;
                  if (orderGuardWait > .zero) {
                    await Future<void>.delayed(orderGuardWait);
                  }
                  if (allowsOrder) {
                    resolver.next();
                  } else {
                    resolver.reject();
                  }
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
    Duration orderGuardWait = const Duration(milliseconds: 1),
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
    router = _StoreRouter(
      isOnWeb ? browser : null,
      orderGuardWait: orderGuardWait,
    );
    if (isOnWeb) browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final bool isOnWeb;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  // The page on top and the url of the app.
  String get shown => '${router.topRoute.name} ${router.currentUrl}';

  // The pages of the root's stack.
  String get stack =>
      router.stack.map((page) => page.routeData.name).join(', ');

  // The pages of the nested router of Orders, with the id of each Order.
  String get orders {
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
  // A guard of Order that answers at once was asked two times too, though
  // Order 7 went on once.
  for (final orderGuardWait in [
    const Duration(milliseconds: 1),
    Duration.zero,
  ]) {
    group('With a guard of Order that waits $orderGuardWait', () {
      testWidgets('on the web, opened at /store/orders/7: Order 7 opens once, '
          'its guard is asked once, and the link keeps one entry', (
        tester,
      ) async {
        final app = _App(
          tester,
          isOnWeb: true,
          orderGuardWait: orderGuardWait,
          launchAt: '/store/orders/7',
        );
        await app.open();

        expect(
          (app.shown, app.orders, app.router.orderAsks, app.browser.held),
          ('Order /store/orders/7', 'Order 7', 1, '>/store/orders/7'),
        );
        // The app wrote over the link's entry alone.
        expect(app.pushesAndSteps, isEmpty);
      });

      testWidgets('off the web, navigatePath from Home: Order 7 opens once, '
          'its guard is asked once, and one back shows Home', (tester) async {
        final app = _App(
          tester,
          isOnWeb: false,
          orderGuardWait: orderGuardWait,
        );
        await app.open();

        unawaited(app.router.navigatePath('/store/orders/7'));
        await app.settle();
        expect(
          (app.shown, app.orders, app.router.orderAsks),
          ('Order /store/orders/7', 'Order 7', 1),
        );

        await tester.binding.handlePopRoute();
        await app.settle();
        expect((app.shown, app.stack), ('Home /', 'Home'));
      });
    });
  }

  // The guard of Order says no: the result is the one a tab guard that
  // answers at once gives.
  group('The guard of Order says no', () {
    testWidgets('on the web, opened at /store/orders/7: the tab Orders shows '
        'its first page, on the one entry of the link', (tester) async {
      final app = _App(tester, isOnWeb: true, launchAt: '/store/orders/7');
      app.router.allowsOrder = false;
      await app.open();

      expect(
        (app.shown, app.orders, app.router.orderAsks, app.browser.held),
        ('OrdersIndex /store/orders', 'OrdersIndex', 1, '>/store/orders'),
      );
      expect(app.pushesAndSteps, isEmpty);
    });

    testWidgets('off the web, navigatePath from Home: Home stays, and '
        'onFailure hears the rejection', (tester) async {
      final app = _App(tester, isOnWeb: false);
      await app.open();
      app.router.allowsOrder = false;

      final failures = <NavigationFailure>[];
      unawaited(
        app.router.navigatePath('/store/orders/7', onFailure: failures.add),
      );
      await app.settle();

      expect((app.shown, app.stack, failures.length), ('Home /', 'Home', 1));
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
    });
  });
}
