import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a guard that shows a sign-in page with redirectUntil when the
// browser's forward button reaches its page, and lets the page in after the
// sign-in, leaves the browser on the entry the user went to. The entries
// ahead stay (callmephil/auto_route_library#37).
//
// Steps: on Home, push Gift, whose guard checks the sign-in, then Other.
// Press the browser's back button two times, onto Home, and sign out. Press
// the forward button: the guard of Gift shows Login on the entry of Gift.
// Sign in: the guard calls next().
// Was: the app asked the browser to write Login over the entry of Gift, to
// step back one entry and to push Gift. The browser then held the entries of
// Home and Gift alone: the entry of Other ahead was lost. Login left before
// Gift went on in its place, and its removal reported the url of Home, the
// page under it. The web history took that url for a step back to the entry
// of Home, and Gift for a new entry after it. The same in a tabs page:
// forward onto Order 7, whose guard shows Login, lost the entry of the
// Account tab ahead.
// Should: Gift takes the place of Login on the entry the user went to, with
// one write over it, and the forward button then shows Other. The app's own
// push of Gift writes Login, then Gift over it, and steps the browser
// nowhere. The neighbor below: a later guard that still decides after the
// sign-in, while the page under Login shows.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal changes no entry and only history.pushState removes the
// entries ahead; and Flutter's Navigator.pushReplacement, which puts a route
// in the place of another in one step.
//
// The same walks run in a real browser in
// test/web/forward_with_sign_in_redirect_web_test.dart, and in the example
// app in example.old/integration_test/forward_with_sign_in_redirect_test.dart.

// The app of the issue: Home, Gift, Other and Login; and Store with the tabs
// Shop, Orders and Account, where Orders holds a nested router with
// OrdersIndex and Order. Gift and Order have a sign-in guard, see
// [_App.signOut]. Gift has a second guard that waits for [_App.held] while
// it is not null.
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

  // While the user is signed out, shows Login and waits for the sign-in.
  // Then, or at once, lets the page in.
  AutoRouteGuard get _signInGuard => .simple((resolver, _) async {
    if (_app._signingIn case final signingIn?) {
      unawaited(resolver.redirectUntil(const NamedRoute<Object?>('Login')));
      await signingIn.future;
    }
    resolver.next();
  });

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    _page('Login', '/login'),
    NamedRouteDef(
      name: 'Gift',
      path: '/gift',
      guards: [
        _signInGuard,
        // A check after the sign-in, as for the gift's stock.
        AutoRouteGuard.simple((resolver, _) async {
          if (_app.held case final check?) await check.future;
          resolver.next();
        }),
      ],
      builder: (_, _) => const Text('Gift'),
    ),
    _page('Other', '/other'),
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
          children: [
            _page('OrdersIndex', ''),
            NamedRouteDef(
              name: 'Order',
              path: ':id',
              guards: [_signInGuard],
              builder: (_, _) => const Text('Order'),
            ),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

// The app of a test, on Home.
class _App {
  new(this.tester) {
    router = _StoreRouter(browser, this);
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  // Completes once the user has signed in; null while signed in.
  Completer<void>? _signingIn;

  // Holds the second guard of Gift until it completes.
  Completer<void>? held;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  Future<void> start() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
  }

  Future<void> pushPath(String path) async {
    unawaited(router.pushPath<Object?>(path));
    await browser.settle(tester);
  }

  // The steps of the issue 31 store: Store on Orders over Home, Order 7 in
  // Orders, then the Account tab.
  Future<void> openAccountAfterOrder() async {
    await pushPath('/store/orders');
    final tabs = router.innerRouterOf<TabsRouter>('Store')!;
    unawaited(
      tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
    );
    await browser.settle(tester);
    tabs.setActiveIndex(2);
    await browser.settle(tester);
  }

  // From now on, a sign-in guard shows Login and waits for [signIn].
  void signOut() => _signingIn = Completer<void>();

  // The user signs in on Login, and the guard that waits lets its page in.
  Future<void> signIn() async {
    _signingIn?.complete();
    _signingIn = null;
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

  // What the app asked of the browser since [from] calls were asked.
  Iterable<String> askedSince(int from) => browser.asked.skip(from);
}

void main() {
  testWidgets('Forward onto Gift, whose guard shows Login, ends on the entry '
      'of Gift after the sign-in and keeps the entry of Other ahead', (
    tester,
  ) async {
    final app = _App(tester);
    await app.start();
    await app.pushPath('/gift');
    await app.pushPath('/other');
    expect(await app.walk(app.browser.didPressBack, 2), [
      'Gift /gift',
      'Home /',
    ]);
    app.signOut();
    final asked = app.browser.asked.length;

    expect(await app.walk(app.browser.didPressForward, 1), ['Login /login']);
    expect(app.browser.held, '/ >/login /other');
    await app.signIn();

    expect(app.shown, 'Gift /gift');
    expect(app.browser.held, '/ >/gift /other');
    expect(app.askedSince(asked), ['replace /login', 'replace /gift']);
    expect(await app.walk(app.browser.didPressForward, 2), ['Other /other']);
    expect(app.browser.held, '/ /gift >/other');
  });

  testWidgets('In Store, forward onto Order 7, whose guard shows Login, ends '
      'on the entry of Order 7 and keeps the entry of Account ahead', (
    tester,
  ) async {
    final app = _App(tester);
    await app.start();
    await app.openAccountAfterOrder();
    // Read before the walk: the entries the browser holds on Account.
    final heldOnAccount = app.browser.held;
    expect(await app.walk(app.browser.didPressBack, 2), [
      'Order /store/orders/7',
      'OrdersIndex /store/orders',
    ]);
    app.signOut();
    final asked = app.browser.asked.length;

    expect(await app.walk(app.browser.didPressForward, 1), ['Login /login']);
    expect(app.browser.held, '/ /store/orders >/login /store/account');
    await app.signIn();

    expect(app.shown, 'Order /store/orders/7');
    expect(app.browser.held, '/ /store/orders >/store/orders/7 /store/account');
    expect(app.askedSince(asked), [
      'replace /login',
      'replace /store/orders/7',
    ]);
    expect(await app.walk(app.browser.didPressForward, 2), [
      'Account /store/account',
    ]);
    expect(
      (heldOnAccount, app.browser.held),
      (
        '/ /store/orders /store/orders/7 >/store/account',
        '/ /store/orders /store/orders/7 >/store/account',
      ),
    );
    expect(await app.walk(app.browser.didPressBack, 4), [
      'Order /store/orders/7',
      'OrdersIndex /store/orders',
      'Home /',
    ]);
  });

  // Steps: on Home, sign out and push Gift: Login shows. Sign in.
  // Was: the app asked the browser for push /login, go -1 and push /gift.
  // Should: push /login, then Gift over it, as Navigator.pushReplacement.
  testWidgets("The app's own push of Gift, whose guard shows Login, writes "
      'Login, then Gift over it', (tester) async {
    final app = _App(tester);
    await app.start();
    app.signOut();
    final asked = app.browser.asked.length;

    await app.pushPath('/gift');
    expect(app.shown, 'Login /login');
    await app.signIn();

    expect(app.shown, 'Gift /gift');
    expect(app.browser.held, '/ >/gift');
    expect(app.askedSince(asked), ['push /login', 'replace /gift']);
  });

  // Steps: the steps of the issue, with the second guard of Gift held after
  // the sign-in. Draw a frame, then let it answer.
  // Should: Home shows while the second guard decides, and the url names
  // it, not Login, which has left. Then Gift shows with its url.
  testWidgets('A later guard that still decides after the sign-in leaves '
      'the url of the page on screen', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.pushPath('/gift');
    await app.pushPath('/other');
    await app.walk(app.browser.didPressBack, 2);
    app.signOut();
    expect(await app.walk(app.browser.didPressForward, 1), ['Login /login']);

    final check = app.held = Completer<void>();
    await app.signIn();
    expect(app.router.topRoute.name, 'Home');
    expect(app.router.urlState.url, '/');
    expect(app.browser.url, '/');

    app.held = null;
    check.complete();
    await app.browser.settle(tester);
    expect(app.shown, 'Gift /gift');
    expect(app.router.urlState.url, '/gift');
  });
}
