@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, with rebuildStackOnDeepLink, the back and forward
// buttons go through each page once and change no entry
// (callmephil/auto_route_library#38). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/rebuild_stack_back_and_forward_test.dart. Here prefix matches are
// off, as on the web by default.
//
// Native behavior this holds to: the HTML standard's session history, where
// a back or forward traversal moves to another entry and adds or changes
// none. Flutter's Navigator keeps the pages under the page that shows
// again.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, A and B, and Store with the tabs Shop, Orders and Account. Orders
// holds a nested router with OrdersIndex and Order.
RootStackRouter _storeRouter() => .build(
  routes: [
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
  ],
);

// The page on top, the pages of the root stack, the browser's url and its
// entry, counted from [home].
String _shown(RootStackRouter router, int home) =>
    '${router.topRoute.name} '
    '[${router.stack.map((page) => page.name).join(' ')}] '
    '$browserPath ${browserSerialCount - home}';

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('Back after a tab change shows Order 7, OrdersIndex, then '
      'Home, and forward walks back to Account', (tester) async {
    final router = _storeRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('Store')!;
    unawaited(
      tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
    );
    await settleBrowser(tester);
    tabs.setActiveIndex(2);
    await settleBrowser(tester);
    expect(browserPath, '/store/account');
    expect(browserSerialCount, home + 3);

    final backWalk = <String>[];
    for (var i = 0; i < 4 && browserSerialCount > home; i++) {
      await pressBrowserBack(tester);
      backWalk.add(_shown(router, home));
    }
    expect(backWalk, [
      'Order [Home Store] /store/orders/7 2',
      'OrdersIndex [Home Store] /store/orders 1',
      'Home [Home] / 0',
    ]);

    final forwardWalk = <String>[];
    for (var i = 0; i < 3; i++) {
      await pressBrowserForward(tester);
      forwardWalk.add(_shown(router, home));
    }
    expect(forwardWalk, [
      'OrdersIndex [Home Store] /store/orders 1',
      'Order [Home Store] /store/orders/7 2',
      'Account [Home Store] /store/account 3',
    ]);
  });

  testWidgets('In a plain stack, back and forward keep Home under the page '
      'they show', (tester) async {
    final router = _storeRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    for (final name in ['A', 'B']) {
      unawaited(router.push(NamedRoute<Object?>(name)));
      await settleBrowser(tester);
    }

    final walk = <String>[];
    for (final press in [
      pressBrowserBack,
      pressBrowserBack,
      pressBrowserForward,
      pressBrowserForward,
    ]) {
      await press(tester);
      walk.add(_shown(router, home));
    }
    expect(walk, [
      'A [Home A] /a 1',
      'Home [Home] / 0',
      'A [Home A] /a 1',
      'B [Home A B] /b 2',
    ]);
  });

  // A url typed into the address bar is a link from the platform: its page
  // replaces the stack, as the flag says.
  testWidgets('A url typed into the address bar still replaces the stack', (
    tester,
  ) async {
    final router = _storeRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('A')));
    await settleBrowser(tester);

    await browserMove(tester, () => window.location.hash = '/b');

    expect(_shown(router, home), 'B [B] /b 2');
  });
}
