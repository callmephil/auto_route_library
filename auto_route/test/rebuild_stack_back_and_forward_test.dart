import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, with rebuildStackOnDeepLink, the browser's back and forward
// buttons go through each page once and change no entry
// (callmephil/auto_route_library#38).
//
// Steps: router.config(rebuildStackOnDeepLink: true). On Home, open Store
// on its Orders tab, open Order 7 in the nested router of Orders, then
// select the Account tab. Press the browser's back button until there is
// no entry before, then its forward button until Account. The same with a
// plain stack: on Home, push A, then B; back twice, forward twice, back
// twice.
// Was: back showed Order 7, then OrdersIndex, then stopped: Home was lost.
// The delegate opened the entry the browser went to as a link that
// rebuilds the stack, and the routes of that entry hold only the way to
// its page. So Home and the pages under the page left, and the history
// wrote the url of OrdersIndex over the entry of Home. Forward then lost
// the entries ahead too. In the plain stack, the first forward press closed
// Home in the same way.
// Should: back shows Order 7, OrdersIndex, then Home, and forward walks the
// same entries up to Account, as without the flag. No press writes an
// entry. A url typed into the address bar is still a link, and its pages
// replace the stack.
//
// Native behavior this holds to: the HTML standard's session history, where
// a back or forward traversal moves to another entry and adds or changes
// none. Flutter's Navigator keeps the pages under the page that shows
// again.
//
// The same walk runs in a real browser in
// test/web/rebuild_stack_back_and_forward_web_test.dart, and in the example
// app in example.old/integration_test/rebuild_stack_back_and_forward_test.dart.

// Home, A and B, and Store with the tabs Shop, Orders and Account. Orders
// holds a nested router with OrdersIndex and Order.
class _StoreRouter extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser _browser;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    // The test's clock runs through every animation at once; the browser
    // of a test lands late, never too late.
    landingLimit: const Duration(hours: 1),
  );

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    _page('A', '/a'),
    _page('B', '/b'),
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
          builder: (_, _) => const AutoRouter(),
          children: [_page('OrdersIndex', ''), _page('Order', ':id')],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

// The app of a test, which rebuilds the stack on deep links.
class _App {
  new(this.tester) {
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final router = _StoreRouter(browser);

  // The page on top, the pages of the root stack and the url the browser
  // shows.
  String get shown =>
      '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] ${browser.url}';

  // The VM's default config, with prefix matches on, as the other tests of
  // the web history use. The VM is off the web, where with prefix matches
  // off a link over the launch page alone takes that page's place, as on
  // an iOS cold start; the web never does that.
  Future<void> start() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await browser.settle(tester);
  }

  // Makes [call], then waits until the browser holds what the app shows.
  Future<void> run(void Function() call) async {
    call();
    await browser.settle(tester);
  }

  // The page shown after each of [presses], until one has no entry to go
  // to.
  Future<List<String>> walk(List<bool Function()> presses) async {
    final shownAfter = <String>[];
    for (final press in presses) {
      if (!press()) break;
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }
}

void main() {
  testWidgets('Back after a tab change shows Order 7, OrdersIndex, then '
      'Home, and forward walks back to Account', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.run(
      () => unawaited(app.router.pushPath<Object?>('/store/orders')),
    );
    final tabs = app.router.innerRouterOf<TabsRouter>('Store')!;
    await app.run(
      () => unawaited(
        tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
      ),
    );
    await app.run(() => tabs.setActiveIndex(2));
    // Read before the walk: the entries the browser holds on Account.
    final heldOnAccount = app.browser.held;
    final asked = app.browser.asked.length;

    final back = app.browser.didPressBack;
    expect(await app.walk([back, back, back, back]), [
      'Order [Home Store] /store/orders/7',
      'OrdersIndex [Home Store] /store/orders',
      'Home [Home] /',
    ]);
    expect(app.browser.held, '>/ /store/orders /store/orders/7 /store/account');

    final forward = app.browser.didPressForward;
    expect(await app.walk([forward, forward, forward, forward]), [
      'OrdersIndex [Home Store] /store/orders',
      'Order [Home Store] /store/orders/7',
      'Account [Home Store] /store/account',
    ]);
    // Back and forward wrote no entry and moved the browser nowhere: on
    // Account again, the browser holds what it held there before the walk.
    const onAccount = '/ /store/orders /store/orders/7 >/store/account';
    expect((heldOnAccount, app.browser.held), (onAccount, onAccount));
    expect(app.browser.asked.skip(asked), isEmpty);
  });

  testWidgets('In a plain stack, back and forward keep Home under the page '
      'they show', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.run(() => unawaited(app.router.push(const NamedRoute('A'))));
    await app.run(() => unawaited(app.router.push(const NamedRoute('B'))));
    final asked = app.browser.asked.length;

    final back = app.browser.didPressBack;
    final forward = app.browser.didPressForward;
    expect(await app.walk([back, back, forward, forward, back, back]), [
      'A [Home A] /a',
      'Home [Home] /',
      'A [Home A] /a',
      'B [Home A B] /b',
      'A [Home A] /a',
      'Home [Home] /',
    ]);
    expect(app.browser.held, '>/ /a /b');
    expect(app.browser.asked.skip(asked), isEmpty);
  });

  // A url typed into the address bar, as with hash urls, is a link from
  // the platform: the browser drops the entries ahead, makes an entry for
  // it and stands there.
  testWidgets('A url typed into the address bar still replaces the stack', (
    tester,
  ) async {
    final app = _App(tester);
    await app.start();
    await app.run(() => unawaited(app.router.push(const NamedRoute('A'))));
    final home = app.router.stack.firstOrNull?.routeData.matchId;

    app.browser.entries
      ..removeRange(app.browser.index + 1, app.browser.entries.length)
      ..add(('/b', null));
    await app.walk([app.browser.didPressForward]);

    // The link's pages replace A and Home: with prefix matches, the VM's
    // default, a new Home is under B; on the web, B is alone.
    expect(app.shown, kIsWeb ? 'B [B] /b' : 'B [Home B] /b');
    expect(app.router.stack.firstOrNull?.routeData.matchId, isNot(home));
  });
}
