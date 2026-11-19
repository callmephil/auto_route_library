import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, the browser's back button after a tab change returns through
// each page once, also when the guard of the tab it goes back into waits
// (callmephil/auto_route_library#31).
//
// Steps: on Home, open Store on its Orders tab, whose guard waits 1 ms and
// then lets the tab in; open Order 7 in the nested router of Orders; select
// the Account tab. Press the browser's back button until Home, then its
// forward button until Account.
// Was: the walk took 8 back presses, and it showed the tab Account again
// and again, and two presses moved the browser forward. The first press
// landed on the entry of Order 7, and the link the app opens for it ended
// while the guard still decided, so the delegate took the link as turned
// down: it wrote the url of the tab on screen, Account, over the entry of
// Order 7. Once the guard let the tab in, the tab change wrote Order 7
// again, as a new entry.
// Should: 3 back presses show Order 7, OrdersIndex, then Home, and neither
// these nor the forward presses that follow change an entry of the browser.
// A guard that says no keeps the tab on screen and its url, as before.
// The neighbors below: a guard of Order, inside the tab, that waits too; a
// guard whose check fails; and a second press while the guard still decides.
//
// Native behavior this holds to: the HTML standard's session history, where
// a back or forward traversal moves to another entry and adds or changes
// none, and each entry stays the page the user saw there. Flutter's Router
// awaits the delegate's setNewRoutePath before it takes the route as
// applied: a link is decided once the guards it waits for have answered.
//
// The same walk runs in a real browser in
// test/web/back_after_tab_change_with_waiting_guard_web_test.dart, and in
// the example app in
// example.old/integration_test/back_after_tab_change_with_waiting_guard_test.dart.

// The app of the issue: Home, then Store with the tabs Shop, Orders and
// Account. Orders holds a nested router with OrdersIndex and Order, and a
// guard that waits [guardWait], and for [held] while it is not null, then
// fails while [fails] says so, or lets the tab in while [allows] says so.
// Order has a guard of its own that waits [orderGuardWait] when it is more
// than zero.
class _StoreRouter extends RootStackRouter {
  new(
    this._browser, {
    required this.guardWait,
    required this.allows,
    required this.fails,
    required this.held,
    required this.orderGuardWait,
  });

  final TestHistoryBrowser _browser;
  final Duration guardWait;
  final bool Function() allows;
  final bool Function() fails;
  final Future<void>? Function() held;
  final Duration orderGuardWait;

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
              if (guardWait > .zero) {
                await Future<void>.delayed(guardWait);
              }
              // A check the test holds open, as one that waits for the
              // network.
              if (held() case final check?) await check;
              if (fails()) throw StateError('The sign-in check failed.');
              if (allows()) {
                resolver.next();
              } else {
                resolver.reject();
              }
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
                if (orderGuardWait > .zero)
                  AutoRouteGuard.simple((resolver, _) async {
                    await Future<void>.delayed(orderGuardWait);
                    resolver.next();
                  }),
              ],
              builder: (_, _) => const Text('Order'),
            ),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

// The app of a test, on Account after the steps of the issue.
class _App {
  new(
    this.tester, {
    required Duration guardWait,
    Duration orderGuardWait = .zero,
  }) {
    router = _StoreRouter(
      browser,
      guardWait: guardWait,
      allows: () => allows,
      fails: () => fails,
      held: () => held?.future,
      orderGuardWait: orderGuardWait,
    );
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  // Whether the guard of Orders lets the tab in.
  bool allows = true;

  // Whether the check of the guard of Orders fails, as a request does while
  // the phone is offline.
  bool fails = false;

  // Holds the check of the guard of Orders open until it completes.
  Completer<void>? held;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // Opens Store on Orders over Home, Order 7 in Orders unless [opensOrder]
  // is false, then Account.
  Future<void> openAccountAfterOrder({bool opensOrder = true}) async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
    unawaited(router.pushPath<Object?>('/store/orders'));
    await browser.settle(tester);
    final tabs = router.innerRouterOf<TabsRouter>('Store')!;
    if (opensOrder) {
      unawaited(
        tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
      );
      await browser.settle(tester);
    }
    tabs.setActiveIndex(2);
    await browser.settle(tester);
  }

  // Presses back, then [then], while the check of the guard of Orders is
  // held, and lets the check answer once the browser has landed on both.
  Future<void> pressBackThenWhileHeld(bool Function() then) async {
    final check = held = Completer<void>();
    browser.didPressBack();
    then();
    await browser.settle(tester);
    held = null;
    check.complete();
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
}

// The entries the browser holds on Account, after the steps of the issue.
const _onAccount = '/ /store/orders /store/orders/7 >/store/account';

void main() {
  const oneMillisecond = Duration(milliseconds: 1);

  // A guard that answers at once is the control: its walk was right before.
  for (final guardWait in [Duration.zero, oneMillisecond]) {
    group('With a tab guard that waits $guardWait', () {
      testWidgets('back shows Order 7, OrdersIndex, then Home, and forward '
          'walks back to Account', (tester) async {
        await _expectWalkOfOneEntryPerPage(_App(tester, guardWait: guardWait));
      });

      // The forward press onto Order 7, which the back walk closed, asks the
      // guard of Order in the nested router of the tab. The back press into
      // Orders asked it again too, once the tab's own guard had let the tab
      // in, until it showed the open Order 7 as it is
      // (callmephil/auto_route_library#36).
      // Was: the 8 presses of the issue. A fix that held the link open for
      // the tab change alone still took 6: Order 7, Account, OrdersIndex,
      // Account, OrdersIndex, Home, as the link ended while the guard of
      // Order decided.
      // Should: the same walk as with no guard on Order.
      testWidgets('with a guard of Order that waits too, back and forward '
          'walk the same entries', (tester) async {
        await _expectWalkOfOneEntryPerPage(
          _App(tester, guardWait: guardWait, orderGuardWait: oneMillisecond),
        );
      });

      testWidgets('a guard that says no to the entry of Order 7 keeps Account '
          'and reports its url', (tester) async {
        final app = _App(tester, guardWait: guardWait);
        await app.openAccountAfterOrder();
        app.allows = false;

        app.browser.didPressBack();
        await app.browser.settle(tester);

        expect(app.shown, 'Account /store/account');
        expect(app.router.urlState.url, '/store/account');
        expect(app.browser.index, 2);
      });

      // The check of the guard fails, as a request does while the phone is
      // offline.
      // Was: after a wait, nothing reported the failure: the link had ended
      // before, and the failure of the tab change was caught and dropped.
      // Should: the failure is reported as an uncaught error, as for the
      // app's own setActiveIndex, and Account stays with its url, as after a
      // no. On the web, a navigation whose handler fails ends with a
      // navigateerror event (MDN, Navigation: navigateerror event).
      testWidgets('a guard that fails on the entry of Order 7 reports its '
          'error and keeps Account', (tester) async {
        final app = _App(tester, guardWait: guardWait);
        await app.openAccountAfterOrder();
        app.fails = true;

        final errors = <Object>[];
        await runZonedGuarded(() async {
          app.browser.didPressBack();
          await app.browser.settle(tester);
        }, (error, _) => errors.add(error));

        expect(errors, [isStateError]);
        expect(app.shown, 'Account /store/account');
        expect(app.router.urlState.url, '/store/account');
        expect(app.browser.index, 2);
      });
    });
  }

  // A second press of the browser's back or forward button while the guard
  // of Orders still decides on the first: the later press is the user's
  // choice, and the first link gives up.
  group('A second press while the tab guard still decides', () {
    // Steps: on Home, open Store on Orders, then select Account. Hold the
    // check of the guard of Orders, press back twice, then let it answer.
    // Was: the app wrote the url of Account over the entry of OrdersIndex
    // while the guard decided: the browser held /, /store/account and
    // /store/account, and forward showed Account twice.
    // Should: Home, on the first entry, and the guard's answer changes
    // nothing: the browser holds its entries as before, and forward walks
    // them.
    testWidgets('back twice, onto Home, ends on Home and keeps the entries', (
      tester,
    ) async {
      final app = _App(tester, guardWait: .zero);
      await app.openAccountAfterOrder(opensOrder: false);
      expect(app.browser.held, '/ /store/orders >/store/account');

      await app.pressBackThenWhileHeld(app.browser.didPressBack);

      expect(app.shown, 'Home /');
      expect(app.browser.held, '>/ /store/orders /store/account');
      expect(await app.walk(app.browser.didPressForward, 8), [
        'OrdersIndex /store/orders',
        'Account /store/account',
      ]);
    });

    // Steps: the steps of the issue, then hold the check of the guard of
    // Orders, press back, then forward, then let it answer.
    // Was: once the guard let Orders in, the app showed Order 7, though the
    // browser stood on the entry of Account, and wrote Order 7 as a new
    // entry after the url of Account it had written over the entry of
    // Order 7.
    // Should: Account stays, the guard's answer changes nothing, and back
    // then shows Order 7, OrdersIndex and Home.
    testWidgets('back, then forward, ends on Account and keeps the entries', (
      tester,
    ) async {
      final app = _App(tester, guardWait: .zero);
      await app.openAccountAfterOrder();

      await app.pressBackThenWhileHeld(app.browser.didPressForward);

      expect(app.shown, 'Account /store/account');
      expect(app.browser.held, _onAccount);
      expect(await app.walk(app.browser.didPressBack, 8), [
        'Order /store/orders/7',
        'OrdersIndex /store/orders',
        'Home /',
      ]);
    });
  });
}

// Walks back from Account until Home, then forward until Account, in
// [app], and expects one entry per page: the walk of the issue.
Future<void> _expectWalkOfOneEntryPerPage(_App app) async {
  await app.openAccountAfterOrder();
  expect(app.shown, 'Account /store/account');
  // Read before the walk: the entries the browser holds on Account.
  final heldOnAccount = app.browser.held;
  final asked = app.browser.asked.length;

  expect(await app.walk(app.browser.didPressBack, 8), [
    'Order /store/orders/7',
    'OrdersIndex /store/orders',
    'Home /',
  ]);
  expect(app.browser.held, '>/ /store/orders /store/orders/7 /store/account');

  expect(await app.walk(app.browser.didPressForward, 8), [
    'OrdersIndex /store/orders',
    'Order /store/orders/7',
    'Account /store/account',
  ]);
  // Back and forward changed no entry: on Account again, the browser holds
  // what it held there before the walk.
  expect((heldOnAccount, app.browser.held), (_onAccount, _onAccount));
  // The app added no entry and moved the browser nowhere. Forward onto the
  // entry of OrdersIndex opens Store again, on Shop while the guard of
  // Orders decides, and the entry names the tab on screen until Orders is
  // let in, as when the app first opened it.
  expect(
    app.browser.asked.skip(asked).where((call) => !call.startsWith('replace ')),
    isEmpty,
  );
}
