import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, the forward button onto the entry of a page in the tab on
// screen changes no entry (callmephil/auto_route_library#54).
//
// Steps: Store shows the tabs Shop and Orders, and Orders holds a nested
// router with OrdersIndex and Order. The browser holds /, /store/orders,
// /store/orders/7, /store/orders/8 and /a, and the app is reloaded on
// /store/orders/8. Press back three times, then forward four times. Or,
// with rebuildStackOnDeepLink, open Store on Orders and Order 7, type
// /store/orders/8, push A, press back four times and forward four times.
// Was: forward onto the entry of an Order that the tab on screen did not
// show stepped the browser back one entry and pushed the url of the entry
// again, which removed the entry of A, so the last forward press found no
// entry.
// Should: no press asks the browser for a step or a write, and the last
// forward press shows A.
//
// A tab whose router the app's widgets manage, AutoRouter.declarative, keeps
// the pages its app gives it: a url typed into it that the app does not take
// leaves Item 7, and the url names Item 7 again, as after a guard's no.
//
// Native behavior this holds to: the HTML standard's session history, where
// a forward traversal goes to the next entry and adds or changes none, and
// only history.pushState removes the entries ahead. Flutter's Router reports
// the delegate's configuration, the page on screen, after setNewRoutePath.

class _Router extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser _browser;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    landingLimit: const Duration(hours: 1),
  );

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    _page('A', '/a'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Orders')],
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
      ],
    ),
  ];
}

// Home, and Store on Orders, an AutoRouter.declarative whose app shows the
// pages [listed] names, an id for an Item.
List<AutoRoute> _declarativeRoutes(ValueNotifier<List<String>> listed) => [
  NamedRouteDef(name: 'Home', path: '/', builder: (_, _) => const Text('Home')),
  NamedRouteDef(
    name: 'Store',
    path: '/store',
    builder: (_, _) => const Scaffold(
      body: AutoTabsRouter(
        routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Orders')],
      ),
    ),
    children: [
      NamedRouteDef(
        name: 'Shop',
        path: 'shop',
        builder: (_, _) => const Text('Shop'),
      ),
      NamedRouteDef(
        name: 'Orders',
        path: 'orders',
        builder: (_, _) => ValueListenableBuilder<List<String>>(
          valueListenable: listed,
          builder: (_, pages, _) => AutoRouter.declarative(
            routes: (_) => [
              for (final page in pages)
                if (page == 'Index')
                  const NamedRoute<Object?>('Index')
                else
                  NamedRoute<Object?>('Item', params: {'id': page}),
            ],
          ),
        ),
        children: [
          NamedRouteDef(
            name: 'Index',
            path: '',
            builder: (_, _) => const Text('Index'),
          ),
          NamedRouteDef(
            name: 'Item',
            path: ':id',
            builder: (_, _) => const Text('Item'),
          ),
        ],
      ),
    ],
  ),
];

class _DeclarativeRouter extends RootStackRouter {
  new(this._browser, this._listed);

  final TestHistoryBrowser _browser;
  final ValueNotifier<List<String>> _listed;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    landingLimit: const Duration(hours: 1),
  );

  @override
  late final List<AutoRoute> routes = _declarativeRoutes(_listed);
}

class _App {
  new(this.tester) {
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final router = _Router(browser);

  // The page on top, the pages of the stack and the browser's entries.
  String get shown =>
      '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] ${browser.held}';

  Future<void> start({required bool rebuildStack}) async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(
        rebuildStackOnDeepLink: rebuildStack,
        includePrefixMatches: false,
      ),
    );
    await browser.settle(tester);
  }

  // What each of [presses] shows and asks of the browser, until one has no
  // entry.
  Future<List<String>> walk(List<bool Function()> presses) async {
    final shownAfter = <String>[];
    for (final press in presses) {
      final asked = browser.asked.length;
      if (!press()) break;
      await browser.settle(tester);
      shownAfter.add('$shown ${browser.asked.skip(asked).toList()}');
    }
    return shownAfter;
  }
}

// The browser's entries in both walks, with the one at [at] marked.
String _held(int at) => [
  for (final (number, url) in [
    '/',
    '/store/orders',
    '/store/orders/7',
    '/store/orders/8',
    '/a',
  ].indexed)
    '${number == at ? '>' : ''}$url',
].join(' ');

void main() {
  testWidgets('After a reload on Order 8 with A ahead, forward walks to A '
      'and changes no entry', (tester) async {
    final app = _App(tester);
    app.browser.entries
      ..clear()
      ..addAll([
        ('/', null),
        ('/store/orders', null),
        ('/store/orders/7', null),
        ('/store/orders/8', null),
        ('/a', null),
      ]);
    app.browser.index = 3;
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/store/orders/8';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await app.start(rebuildStack: false);

    final back = app.browser.didPressBack;
    final forward = app.browser.didPressForward;
    expect(
      await app.walk([back, back, back, forward, forward, forward, forward]),
      [
        'Order [Store] ${_held(2)} []',
        'OrdersIndex [Store] ${_held(1)} []',
        'Home [Home] ${_held(0)} []',
        'OrdersIndex [Home Store] ${_held(1)} []',
        'Order [Home Store] ${_held(2)} []',
        'Order [Home Store] ${_held(3)} []',
        'A [Home Store A] ${_held(4)} []',
      ],
    );
  });

  testWidgets('After a typed url to Order 8 in the tab on screen and a push '
      'of A, forward walks back to A and changes no entry', (tester) async {
    final app = _App(tester);
    await app.start(rebuildStack: true);
    unawaited(app.router.pushPath<Object?>('/store/orders'));
    await app.browser.settle(tester);
    final tabs = app.router.innerRouterOf<TabsRouter>('Store')!;
    unawaited(
      tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
    );
    await app.browser.settle(tester);
    app.browser.entries
      ..removeRange(app.browser.index + 1, app.browser.entries.length)
      ..add(('/store/orders/8', null));
    app.browser.didPressForward();
    await app.browser.settle(tester);
    unawaited(app.router.push(const NamedRoute<Object?>('A')));
    await app.browser.settle(tester);
    expect(app.shown, 'A [Store A] ${_held(4)}');

    final back = app.browser.didPressBack;
    final forward = app.browser.didPressForward;
    expect(
      await app.walk([
        ...[back, back, back, back],
        ...[forward, forward, forward, forward],
      ]),
      [
        'Order [Store] ${_held(3)} []',
        'Order [Store] ${_held(2)} []',
        'OrdersIndex [Store] ${_held(1)} []',
        'Home [Home] ${_held(0)} []',
        'OrdersIndex [Home Store] ${_held(1)} []',
        'Order [Home Store] ${_held(2)} []',
        'Order [Home Store] ${_held(3)} []',
        'A [Home Store A] ${_held(4)} []',
      ],
    );
  });

  testWidgets('A typed url that the declarative router of the tab on screen '
      'does not take steps back to the entry of the page shown', (
    tester,
  ) async {
    final listed = ValueNotifier<List<String>>(['Index']);
    addTearDown(listed.dispose);
    final browser = TestHistoryBrowser()..reportLandingsTo(tester);
    final router = _DeclarativeRouter(browser, listed);
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
    unawaited(router.pushPath<Object?>('/store/orders'));
    await browser.settle(tester);
    listed.value = ['Index', '7'];
    await browser.settle(tester);
    final before = '${router.currentUrl} ${browser.held}';

    browser.entries
      ..removeRange(browser.index + 1, browser.entries.length)
      ..add(('/store/orders/8', null));
    browser.didPressForward();
    await browser.settle(tester);

    final top = router.topRoute;
    expect(
      (
        before,
        '${top.name} ${top.params.optString('id') ?? '-'} ${router.currentUrl} '
            '${browser.held}',
      ),
      (
        '/store/orders/7 / /store/orders >/store/orders/7',
        'Item 7 /store/orders/7 / /store/orders >/store/orders/7 '
            '/store/orders/8',
      ),
    );
  });

  testWidgets(
    'Off the web, a link that the declarative router of the tab on screen '
    'does not take leaves the url of the page shown',
    (tester) async {
      final listed = ValueNotifier<List<String>>(['Index']);
      addTearDown(listed.dispose);
      final router = RootStackRouter.build(routes: _declarativeRoutes(listed));
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.pushPath<Object?>('/store/orders'));
      await tester.pumpAndSettle();
      listed.value = ['Index', '7'];
      await tester.pumpAndSettle();

      await tester.binding.handlePushRoute('/store/orders/8');
      await tester.pumpAndSettle();

      final top = router.topRoute;
      expect(
        '${top.name} ${top.params.optString('id') ?? '-'} '
            '${router.navigationHistory.urlState.url} '
            '${router.isPathActive('/store/orders/8')}',
        'Item 7 /store/orders/7 false',
      );
    },
    skip: kIsWeb,
  );
}
