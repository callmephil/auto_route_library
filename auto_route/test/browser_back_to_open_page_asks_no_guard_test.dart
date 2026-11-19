import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a press of the browser's back or forward button to an entry
// whose page is still open asks no guard of the open pages on the way
// (callmephil/auto_route_library#36).
//
// Steps: on Home, open Store on its Orders tab, open Order 7 in the nested
// router of Orders, then select the Account tab. Press the browser's back
// button. Every stack route has the app's global guard, Store and Order have
// a guard of their own, and the Orders tab has a guard that waits 0 ms or
// 1 ms. Each guard notes the route it is asked for.
// Was: the back press asked the guards of Store and of Order 7 again. Store
// is the tabs page on screen, and Order 7 is open in the tab not on screen.
// The global guard and the route's own guard of each were asked. The app
// opens the entry as a link to its routes, and each stack put the open page
// it reached again on anew, through its guards. The back press from Settings
// to Mail, whose nested router holds message 77, asked the guards of Mail
// and of the message again too.
// Should: only the guard of the Orders tab is asked, as the app's own tab
// change asks it, and Store and Order 7 show as they are. A page that is not
// open, as Order 7 once the back walk has closed it, is asked as before.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal shows the page the user saw at the entry, and Flutter's
// Navigator.pop, which asks nothing of the route under it: that route gets
// only didPopNext. UITabBarController shows the navigation stack of the
// selected tab as it is. Off the web, the fork's back() asks no guard of the
// page it shows again once the pages above it are off
// (callmephil/auto_route_library#16).
//
// The same steps run in a real browser in
// test/web/browser_back_to_open_page_asks_no_guard_web_test.dart, and in the
// example app in
// example.old/integration_test/browser_back_to_open_page_asks_no_guard_test.dart.

// Home, then Store with the tabs Shop, Orders and Account, Mail with Inbox
// and Message, and Settings. Orders holds a nested router with OrdersIndex
// and Order, and a guard that waits [tabGuardWait]. Each guard notes its
// route in [asked]: the app's global guard as 'global' and the route, the
// others by the route alone.
class _StoreRouter extends RootStackRouter {
  new(this._browser, {required this.tabGuardWait});

  final TestHistoryBrowser _browser;
  final Duration tabGuardWait;

  // The routes the guards were asked for, in order.
  final asked = <String>[];

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    // The test's clock runs through every animation at once; the browser
    // of a test lands late, never too late.
    landingLimit: const Duration(hours: 1),
  );

  @override
  late final List<AutoRouteGuard> guards = [
    AutoRouteGuard.simple((resolver, _) {
      asked.add('global ${resolver.routeName}');
      resolver.next();
    }),
  ];

  // A guard of the route [name] that notes its ask and lets the route in.
  AutoRouteGuard _noting(String name) => .simple((resolver, _) {
    asked.add(name);
    resolver.next();
  });

  NamedRouteDef _page(String name, String path, {bool isGuarded = false}) =>
      .new(
        name: name,
        path: path,
        guards: [if (isGuarded) _noting(name)],
        builder: (_, _) => Text(name),
      );

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      guards: [_noting('Store')],
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
              asked.add('Orders');
              if (tabGuardWait > .zero) {
                await Future<void>.delayed(tabGuardWait);
              }
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndex', ''),
            _page('Order', ':id', isGuarded: true),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
    NamedRouteDef(
      name: 'Mail',
      path: '/mail',
      guards: [_noting('Mail')],
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [_page('Inbox', ''), _page('Message', ':id', isGuarded: true)],
    ),
    _page('Settings', '/settings'),
  ];
}

// The app of a test.
class _App {
  new(this.tester, {Duration tabGuardWait = .zero}) {
    router = _StoreRouter(browser, tabGuardWait: tabGuardWait);
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _StoreRouter router;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // The urls of the browser's entries.
  List<String> get entries => [for (final (url, _) in browser.entries) url];

  // Shows the app on Home.
  Future<void> open() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
  }

  // Opens Store on Orders over Home, Order 7 in Orders, then Account.
  Future<void> openAccountAfterOrder() async {
    await open();
    unawaited(router.pushPath<Object?>('/store/orders'));
    await browser.settle(tester);
    final tabs = router.innerRouterOf<TabsRouter>('Store')!;
    unawaited(
      tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
    );
    await browser.settle(tester);
    tabs.setActiveIndex(2);
    await browser.settle(tester);
  }

  // Presses the browser's button [press], and answers the page then shown,
  // the routes whose guards the press asked, and whether the press left the
  // browser's entries as they were.
  Future<(String, String, bool)> afterPress(bool Function() press) async {
    final entriesBefore = entries.join(' ');
    router.asked.clear();
    expect(press(), isTrue);
    await browser.settle(tester);
    final asked = router.asked;
    return (
      shown,
      asked.isEmpty ? 'no guard' : asked.join(', '),
      entries.join(' ') == entriesBefore,
    );
  }
}

void main() {
  const oneMillisecond = Duration(milliseconds: 1);

  for (final tabGuardWait in [Duration.zero, oneMillisecond]) {
    group('With a guard of the Orders tab that waits $tabGuardWait', () {
      // Was: global Store, Store, Orders, global Order and Order.
      testWidgets('back into Orders shows Order 7 and asks only the guard of '
          'the tab', (tester) async {
        final app = _App(tester, tabGuardWait: tabGuardWait);
        await app.openAccountAfterOrder();
        expect(app.shown, 'Account /store/account');

        expect(await app.afterPress(app.browser.didPressBack), (
          'Order /store/orders/7',
          'Orders',
          true,
        ));
      });

      // Was: global Store and Store, for the change back to Account.
      testWidgets('forward to Account, then back into Orders again, asks only '
          'the guard of the tab', (tester) async {
        final app = _App(tester, tabGuardWait: tabGuardWait);
        await app.openAccountAfterOrder();
        await app.afterPress(app.browser.didPressBack);

        expect(await app.afterPress(app.browser.didPressForward), (
          'Account /store/account',
          'no guard',
          true,
        ));
        expect(await app.afterPress(app.browser.didPressBack), (
          'Order /store/orders/7',
          'Orders',
          true,
        ));
      });

      // The back walk closes Order 7, so forward opens it anew: its guards
      // are asked, as the browser's forward button asks those of a page
      // that is not open. Store, open, is not asked.
      // Was: global Store and Store before the guards of Order.
      testWidgets('forward onto Order 7 after the back walk closed it asks '
          'its guards', (tester) async {
        final app = _App(tester, tabGuardWait: tabGuardWait);
        await app.openAccountAfterOrder();
        await app.afterPress(app.browser.didPressBack);
        expect(await app.afterPress(app.browser.didPressBack), (
          'OrdersIndex /store/orders',
          'no guard',
          true,
        ));

        expect(await app.afterPress(app.browser.didPressForward), (
          'Order /store/orders/7',
          'global Order, Order',
          true,
        ));
      });
    });
  }

  // Steps: on Home, open message 77 in Mail with navigatePath, then push
  // Settings. Press the browser's back button.
  // Was: global Mail, Mail, global Message and Message.
  testWidgets('back from Settings to Mail shows message 77 and asks no '
      'guard', (tester) async {
    final app = _App(tester);
    await app.open();
    unawaited(app.router.navigatePath('/mail/77'));
    await app.browser.settle(tester);
    unawaited(app.router.push(const NamedRoute('Settings')));
    await app.browser.settle(tester);
    expect(app.shown, 'Settings /settings');

    expect(await app.afterPress(app.browser.didPressBack), (
      'Message /mail/77',
      'no guard',
      true,
    ));
  });
}
