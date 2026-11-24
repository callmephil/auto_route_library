@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, a back press onto a page in a tab not on screen, whose
// guard shows a sign-in page with redirectUntil, writes the sign-in page
// over the entry the browser goes to, and the page takes the entry back
// after the sign-in (callmephil/auto_route_library#44). The steps, what was
// seen and what should be seen are those of the headless test on the VM:
// test/back_into_tab_with_sign_in_redirect_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal adds and changes no entry and history.replaceState writes over
// the current entry; and Flutter's Navigator.pushReplacement, which puts a
// route in the place of another.

// Completes once the user has signed in; null while signed in.
Completer<void>? _signingIn;

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home and Login; and Store with the tabs Shop, Orders and Account, where
// Orders holds a nested router with OrdersIndex and Order. While the user
// is signed out, the guard of Orders shows Login and waits for the sign-in.
RootStackRouter _storeRouter() => .build(
  routes: [
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
              if (_signingIn case final signingIn?) {
                unawaited(
                  resolver.redirectUntil(const NamedRoute<Object?>('Login')),
                );
                await signingIn.future;
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
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  tearDown(() => _signingIn = null);

  // Opens Store on Orders, Order 7 in Orders, then the Account tab, and
  // answers the page on top, its url and its entry after the first one.
  Future<String Function()> openAccountAfterOrder(WidgetTester tester) async {
    final router = _storeRouter();
    await pumpRouterConfigApp(tester, router.config());
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
    return () =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
  }

  // Steps: the steps of the issue. Sign out, press the back button: Login
  // shows on the entry of Order 7. Sign in, then press the back button
  // until Home and the forward button until Account.
  testWidgets('Back onto Order 7, whose tab guard shows Login, ends on the '
      'entry of Order 7 and keeps the entry of Account ahead', (tester) async {
    final shown = await openAccountAfterOrder(tester);
    expect(shown(), 'Account /store/account 3');
    _signingIn = Completer<void>();

    await pressBrowserBack(tester);
    expect(shown(), 'Login /login 2');
    _signingIn?.complete();
    _signingIn = null;
    await settleBrowser(tester);
    expect(shown(), 'Order /store/orders/7 2');

    final walk = <String>[];
    for (final press in [pressBrowserBack, pressBrowserBack]) {
      await press(tester);
      walk.add(shown());
    }
    for (var i = 0; i < 3; i++) {
      await pressBrowserForward(tester);
      walk.add(shown());
    }
    expect(walk, [
      'OrdersIndex /store/orders 1',
      'Home / 0',
      'OrdersIndex /store/orders 1',
      'Order /store/orders/7 2',
      'Account /store/account 3',
    ]);
  });

  // Steps: the steps of the issue up to Login, then press the back button
  // again: the browser goes to the entry of OrdersIndex.
  testWidgets('A second back press on Login goes to the entry of '
      'OrdersIndex', (tester) async {
    final shown = await openAccountAfterOrder(tester);
    _signingIn = Completer<void>();
    await pressBrowserBack(tester);
    expect(shown(), 'Login /login 2');

    await pressBrowserBack(tester);
    expect(shown(), endsWith(' 1'));
  });
}
