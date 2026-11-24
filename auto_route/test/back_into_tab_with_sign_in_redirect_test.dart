import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a back press onto a page in a tab not on screen, whose guard
// shows a sign-in page with redirectUntil, writes the sign-in page over the
// entry the browser goes to (callmephil/auto_route_library#44).
//
// Steps: on Home, open Store on Orders, Order 7 in Orders, then the Account
// tab. Sign out and press the browser's back button: the guard of Orders
// shows Login. Sign in, then press back until Home and forward until
// Account.
// Was: the app stepped the browser forward one entry and pushed Login after
// the entry of Account, which then stood under Login. After the sign-in,
// Order 7 had a second entry, and back showed Account, Order 7, OrdersIndex
// and Home. A second back press on Login went to the entry of Account.
// Should: Login takes the entry of Order 7, the browser moves to no other
// entry, and Order 7 takes the entry back after the sign-in. Back shows
// OrdersIndex and Home, and forward walks the same entries up to Account.
// The neighbors below: a second back press on Login, a forward press into
// the tab, a sign-in that fails, and a tab change after the sign-in.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal adds and changes no entry and history.replaceState writes over
// the current entry; and Flutter's Navigator.pushReplacement, which puts a
// route in the place of another.
//
// The same walks run in a real browser in
// test/web/back_into_tab_with_sign_in_redirect_web_test.dart, and in the
// example app in
// example.old/integration_test/back_into_tab_with_sign_in_redirect_test.dart.

// The app of the issue: Home and Login; and Store with the tabs Shop, Orders
// and Account, where Orders holds a nested router with OrdersIndex and
// Order, and a sign-in guard, see [_App.signOut].
class _StoreRouter extends RootStackRouter {
  new(this._browser, this._app);

  final TestHistoryBrowser _browser;
  final _App _app;

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
    _page('Login', '/login'),
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
            AutoRouteGuard.simple((resolver, _) async {
              if (_app._signingIn case final signingIn?) {
                unawaited(
                  resolver.redirectUntil(const NamedRoute<Object?>('Login')),
                );
                if (!await signingIn.future) return resolver.reject();
              }
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [_page('OrdersIndex', ''), _page('Order', ':id')],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

class _App {
  new(this.tester) {
    router = _StoreRouter(browser, this);
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  // Completes with whether the sign-in worked; null while signed in.
  Completer<bool>? _signingIn;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  TabsRouter get tabs => router.innerRouterOf('Store')!;

  Future<void> start() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
  }

  Future<void> pushPath(String path) async {
    unawaited(router.pushPath<Object?>(path));
    await browser.settle(tester);
  }

  Future<void> pushOrder7() async {
    unawaited(
      tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
    );
    await browser.settle(tester);
  }

  Future<void> selectTab(int index) async {
    tabs.setActiveIndex(index);
    await browser.settle(tester);
  }

  // The steps of the issue: Store on Orders over Home, Order 7 in Orders,
  // then the Account tab.
  Future<void> openAccountAfterOrder() async {
    await start();
    await pushPath('/store/orders');
    await pushOrder7();
    await selectTab(2);
  }

  // From now on, the guard of Orders shows Login and waits for [signIn].
  void signOut() => _signingIn = Completer<bool>();

  // The user signs in on Login, or fails to when [succeeds] is false.
  Future<void> signIn({bool succeeds = true}) async {
    _signingIn?.complete(succeeds);
    _signingIn = null;
    await browser.settle(tester);
  }

  // The page shown after each press, at most [limit], while one lands.
  Future<List<String>> walk(bool Function() press, int limit) async {
    final shownAfter = <String>[];
    for (var i = 0; i < limit && press(); i++) {
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }

  // The steps and new entries the app asked for since [from] calls.
  Iterable<String> movesSince(int from) =>
      browser.asked.skip(from).where((call) => !call.startsWith('replace '));
}

const _onAccount = '/ /store/orders /store/orders/7 >/store/account';

void main() {
  testWidgets('Back onto Order 7, whose tab guard shows Login, writes Login '
      'over its entry and keeps the entry of Account ahead', (tester) async {
    final app = _App(tester);
    await app.openAccountAfterOrder();
    final heldOnAccount = app.browser.held;
    app.signOut();
    final asked = app.browser.asked.length;

    expect(await app.walk(app.browser.didPressBack, 1), ['Login /login']);
    expect(app.browser.held, '/ /store/orders >/login /store/account');
    await app.signIn();

    expect(app.shown, 'Order /store/orders/7');
    expect(app.browser.held, '/ /store/orders >/store/orders/7 /store/account');
    expect(app.browser.asked.skip(asked), [
      'replace /login',
      'replace /store/orders/7',
    ]);
    expect(await app.walk(app.browser.didPressBack, 4), [
      'OrdersIndex /store/orders',
      'Home /',
    ]);
    expect(await app.walk(app.browser.didPressForward, 4), [
      'OrdersIndex /store/orders',
      'Order /store/orders/7',
      'Account /store/account',
    ]);
    expect((heldOnAccount, app.browser.held), (_onAccount, _onAccount));
  });

  // Should: the browser goes to the entry before the entry of Order 7, and
  // the app moves it nowhere else. The page there asks the guard of Orders
  // again.
  testWidgets('A second back press on Login goes to the entry of '
      'OrdersIndex', (tester) async {
    final app = _App(tester);
    await app.openAccountAfterOrder();
    app.signOut();
    await app.walk(app.browser.didPressBack, 1);
    final asked = app.browser.asked.length;

    expect(app.browser.didPressBack(), isTrue);
    await app.browser.settle(tester);

    expect(app.browser.index, 1);
    expect(app.movesSince(asked), isEmpty);
    expect(app.browser.entries.map((entry) => entry.$1), [
      '/',
      anything,
      anything,
      '/store/account',
    ]);
  });

  // Steps: on Home, open Store on Account, then Orders and Order 7. Press
  // back two times, onto Account, sign out and press forward.
  // Was: Login went on a new entry, which dropped the entry of Order 7, and
  // after the sign-in the app stepped back: forward showed Login again.
  // Should: Login, then OrdersIndex, on the entry of OrdersIndex.
  testWidgets('Forward onto OrdersIndex, whose tab guard shows Login, '
      'keeps the entry of Order 7 ahead', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.pushPath('/store/account');
    await app.selectTab(1);
    await app.pushOrder7();
    expect(await app.walk(app.browser.didPressBack, 2), [
      'OrdersIndex /store/orders',
      'Account /store/account',
    ]);
    app.signOut();
    final asked = app.browser.asked.length;

    expect(await app.walk(app.browser.didPressForward, 1), ['Login /login']);
    await app.signIn();

    expect(app.shown, 'OrdersIndex /store/orders');
    expect(app.browser.held, '/ /store/account >/store/orders /store/orders/7');
    expect(app.movesSince(asked), isEmpty);
    expect(await app.walk(app.browser.didPressForward, 2), [
      'Order /store/orders/7',
    ]);
  });

  // Should: Account stays, as when the guard keeps the tab out at once, and
  // the app moves the browser nowhere.
  testWidgets('A sign-in that fails keeps Account and the entry of Account '
      'ahead', (tester) async {
    final app = _App(tester);
    await app.openAccountAfterOrder();
    app.signOut();
    final asked = app.browser.asked.length;
    await app.walk(app.browser.didPressBack, 1);

    await app.signIn(succeeds: false);

    expect(app.shown, 'Account /store/account');
    expect(app.browser.index, 2);
    expect(app.movesSince(asked), isEmpty);
    expect(app.browser.entries.lastOrNull?.$1, '/store/account');
  });

  // Should: a new entry. Login alone took the entry, while the guard decided.
  testWidgets("The app's own tab change after the sign-in is a new entry", (
    tester,
  ) async {
    final app = _App(tester);
    await app.openAccountAfterOrder();
    app.signOut();
    await app.walk(app.browser.didPressBack, 1);
    await app.signIn();

    await app.selectTab(0);

    expect(app.shown, 'Shop /store/shop');
    expect(app.browser.held, '/ /store/orders /store/orders/7 >/store/shop');
  });
}
