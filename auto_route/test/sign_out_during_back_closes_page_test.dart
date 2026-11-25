import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a sign-out closes a guarded page that a press of the browser's
// back button shows again while the guard of that page decides.
//
// Steps: on Home, open Store on its Orders tab, Order 7 in Orders, then the
// Account tab. The session check gets slow, and the user signs out: the
// reevaluation asks the guard of Order 7, which waits for the check. The
// user presses the browser's back button into Orders. Then the check ends.
// The same with the guard on Store, and on Shell, whose nested router is not
// built while Cover covers it (maintainState false).
// Was: the press put a new page in place of the open one, so the guard's no
// was dropped as too late: the page stayed on screen.
// Should: the no closes the page, as with no press, and a yes keeps it.
//
// Native behavior this holds to: a back traversal of the HTML standard's
// session history changes only which entry is current, and Flutter's
// Navigator.pop shows the same route under it. The pages list of a sign-out
// leaves the page out, so the Navigator removes it: the latest change wins.

// The session that the router asks its guards again for.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  // A slow check of the session, which the guard waits for.
  Completer<void>? check;

  int asks = 0;

  // A sign-out, or a renewal that keeps the user signed in.
  void change({required bool signsOut}) {
    if (signsOut) isSignedIn = false;
    notifyListeners();
  }
}

// Home, Store with the tabs Shop, Orders and Account, Shell with A and B,
// and Cover. Orders holds a nested router with OrdersIndex and Order. The
// route named [guarded] has a guard that waits for the session check.
class _StoreRouter extends RootStackRouter {
  new(this._browser, this._session, {required this.guarded});

  final TestHistoryBrowser _browser;
  final _Session _session;
  final String guarded;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    landingLimit: const Duration(hours: 1),
  );

  List<AutoRouteGuard> _guardsOf(String name) => [
    if (name == guarded)
      AutoRouteGuard.simple((resolver, _) async {
        _session.asks++;
        if (_session.check case final check?) await check.future;
        _session.isSignedIn ? resolver.next() : resolver.reject();
      }),
  ];

  NamedRouteDef _page(String name, String path) => .new(
    name: name,
    path: path,
    guards: _guardsOf(name),
    builder: (_, _) => Text(name),
  );

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      guards: _guardsOf('Store'),
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
    NamedRouteDef(
      name: 'Shell',
      path: '/shell',
      maintainState: false,
      guards: _guardsOf('Shell'),
      builder: (_, _) => const AutoRouter(),
      children: [_page('A', ''), _page('B', 'b')],
    ),
    _page('Cover', '/cover'),
  ];
}

typedef _Opening = Future<void> Function(
  WidgetTester tester,
  _StoreRouter router,
  TestHistoryBrowser browser,
);

// Opens the app on Home and runs [open]. Then the user signs out, or with
// [staysSignedIn] renews the session, and presses back while the check
// waits. Answers the url and the page on top after the press, how many times
// the guard was asked, and the url, the pages of the root and the page on
// top once the check has ended.
Future<(String, int, String)> _signOutDuringBack(
  WidgetTester tester, {
  required String guarded,
  required _Opening open,
  bool staysSignedIn = false,
}) async {
  final session = _Session();
  addTearDown(session.dispose);
  final browser = TestHistoryBrowser()..reportLandingsTo(tester);
  final router = _StoreRouter(browser, session, guarded: guarded);
  addTearDown(router.navigationHistory.dispose);
  await pumpRouterConfigApp(
    tester,
    router.config(reevaluateListenable: session),
  );
  await browser.settle(tester);
  await open(tester, router, browser);
  final check = Completer<void>();
  session
    ..check = check
    ..asks = 0
    ..change(signsOut: !staysSignedIn);
  await browser.settle(tester);
  expect(browser.didPressBack(), isTrue);
  await browser.settle(tester);
  final afterPress = '${browser.url} ${router.topRoute.name}';
  final asks = session.asks;
  check.complete();
  await browser.settle(tester);
  expect(tester.takeException(), isNull);
  final pages = router.stackData.map((data) => data.name).join(',');
  return (afterPress, asks, '${browser.url} $pages ${router.topRoute.name}');
}

// Opens Store on Orders, Order 7 in Orders, then the Account tab.
Future<void> _openAccountAfterOrder(
  WidgetTester tester,
  _StoreRouter router,
  TestHistoryBrowser browser,
) async {
  unawaited(router.pushPath<Object?>('/store/orders'));
  await browser.settle(tester);
  final tabs = router.innerRouterOf<TabsRouter>('Store')!;
  unawaited(tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'));
  await browser.settle(tester);
  tabs.setActiveIndex(2);
  await browser.settle(tester);
}

// Opens B in Shell, then Cover over Shell, whose nested router then goes.
Future<void> _openCoverOverB(
  WidgetTester tester,
  _StoreRouter router,
  TestHistoryBrowser browser,
) async {
  unawaited(router.pushPath<Object?>('/shell'));
  await browser.settle(tester);
  unawaited(router.innerRouterOf<StackRouter>('Shell')!.pushPath<Object?>('b'));
  await browser.settle(tester);
  unawaited(router.pushPath<Object?>('/cover'));
  await browser.settle(tester);
  expect(router.innerRouterOf<StackRouter>('Shell'), isNull);
}

void main() {
  for (final staysSignedIn in [false, true]) {
    testWidgets(
      staysSignedIn
          ? 'A check that keeps the user signed in keeps Order 7 that a back '
                'press shows meanwhile'
          : 'A sign-out closes Order 7 that a back press shows meanwhile',
      (tester) async {
        final end = staysSignedIn
            ? '/store/orders/7 Home,Store Order'
            : '/store/orders Home,Store OrdersIndex';
        expect(
          await _signOutDuringBack(
            tester,
            guarded: 'Order',
            staysSignedIn: staysSignedIn,
            open: _openAccountAfterOrder,
          ),
          ('/store/orders/7 Order', 1, end),
        );
      },
    );
  }

  testWidgets('A sign-out closes Store, the tabs page that a back press shows '
      'meanwhile', (tester) async {
    expect(
      await _signOutDuringBack(
        tester,
        guarded: 'Store',
        open: _openAccountAfterOrder,
      ),
      ('/store/orders/7 Order', 1, '/ Home Home'),
    );
  });

  testWidgets('A sign-out closes Shell that a back press shows meanwhile, '
      'before its nested router is built again', (tester) async {
    expect(
      await _signOutDuringBack(tester, guarded: 'Shell', open: _openCoverOverB),
      ('/shell/b B', 1, '/ Home Home'),
    );
  });
}
