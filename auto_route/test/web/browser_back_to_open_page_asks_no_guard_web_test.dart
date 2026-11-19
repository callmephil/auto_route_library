@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, a press of the back or forward button to an entry whose
// page is still open asks no guard of the open pages on the way
// (callmephil/auto_route_library#36). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/browser_back_to_open_page_asks_no_guard_test.dart. The guard of the
// Orders tab waits 1 ms here.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal shows the page the user saw at the entry, and Flutter's
// Navigator.pop, which asks nothing of the route under it.

// Home, then Store with the tabs Shop, Orders and Account, Mail with Inbox
// and Message, and Settings. Every stack route has the global guard, and
// Store, Order, Mail and Message a guard of their own. The guard of the
// Orders tab waits 1 ms. Each guard adds the route it is asked for to
// [asked]: the global guard as 'global' and the route, the others by the
// route alone.
RootStackRouter _router(List<String> asked) {
  AutoRouteGuard noting(String name) => .simple((resolver, _) {
    asked.add(name);
    resolver.next();
  });
  NamedRouteDef page(String name, String path, {bool isGuarded = false}) =>
      .new(
        name: name,
        path: path,
        guards: [if (isGuarded) noting(name)],
        builder: (_, _) => Text(name),
      );

  return .build(
    guards: [
      AutoRouteGuard.simple((resolver, _) {
        asked.add('global ${resolver.routeName}');
        resolver.next();
      }),
    ],
    routes: [
      page('Home', '/'),
      NamedRouteDef(
        name: 'Store',
        path: '/store',
        guards: [noting('Store')],
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
          page('Shop', 'shop'),
          NamedRouteDef(
            name: 'Orders',
            path: 'orders',
            guards: [
              // A sign-in check that waits, as for a token in storage.
              AutoRouteGuard.simple((resolver, _) async {
                asked.add('Orders');
                await Future<void>.delayed(const Duration(milliseconds: 1));
                resolver.next();
              }),
            ],
            builder: (_, _) => const AutoRouter(),
            children: [
              page('OrdersIndex', ''),
              page('Order', ':id', isGuarded: true),
            ],
          ),
          page('Account', 'account'),
        ],
      ),
      NamedRouteDef(
        name: 'Mail',
        path: '/mail',
        guards: [noting('Mail')],
        builder: (_, _) => const Scaffold(body: AutoRouter()),
        children: [page('Inbox', ''), page('Message', ':id', isGuarded: true)],
      ),
      page('Settings', '/settings'),
    ],
  );
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('Back into Orders shows Order 7 and asks only the guard of the '
      'tab, and forward onto Order 7 once closed asks its guards', (
    tester,
  ) async {
    final asked = <String>[];
    final router = _router(asked);
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
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

    // Back into Orders, forward to Account, back into Orders again, back to
    // OrdersIndex, which closes Order 7, and forward onto Order 7.
    final shown = <String>[];
    for (final press in [
      pressBrowserBack,
      pressBrowserForward,
      pressBrowserBack,
      pressBrowserBack,
      pressBrowserForward,
    ]) {
      shown.add(await _afterPress(tester, router, asked, press));
    }
    expect(shown, [
      'Order /store/orders/7: Orders',
      'Account /store/account: no guard',
      'Order /store/orders/7: Orders',
      'OrdersIndex /store/orders: no guard',
      'Order /store/orders/7: global Order, Order',
    ]);
  });

  testWidgets('Back from Settings to Mail shows message 77 and asks no guard', (
    tester,
  ) async {
    final asked = <String>[];
    final router = _router(asked);
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.navigatePath('/mail/77'));
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('Settings')));
    await settleBrowser(tester);
    expect(browserPath, '/settings');

    expect(
      await _afterPress(tester, router, asked, pressBrowserBack),
      'Message /mail/77: no guard',
    );
  });
}

// Runs [press], a press of a browser button, and answers the page then on
// top, the url, and the routes whose guards the press asked.
Future<String> _afterPress(
  WidgetTester tester,
  StackRouter router,
  List<String> asked,
  Future<void> Function(WidgetTester) press,
) async {
  asked.clear();
  await press(tester);
  final guards = asked.isEmpty ? 'no guard' : asked.join(', ');
  return '${router.topRoute.name} $browserPath: $guards';
}
