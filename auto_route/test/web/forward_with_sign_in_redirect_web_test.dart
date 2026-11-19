@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, a guard that shows a sign-in page with redirectUntil
// when the forward button reaches its page, and lets the page in after the
// sign-in, leaves the browser on the entry the user went to, and the entries
// ahead stay (callmephil/auto_route_library#37). The steps, what was seen
// and what should be seen are those of the headless test on the VM:
// test/forward_with_sign_in_redirect_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal changes no entry and only history.pushState removes the
// entries ahead; and Flutter's Navigator.pushReplacement, which puts a route
// in the place of another in one step.

// Completes once the user has signed in; null while signed in.
Completer<void>? _signingIn;

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// While the user is signed out, shows Login and waits for the sign-in. Then,
// or at once, lets the page in.
final _signInGuard = AutoRouteGuard.simple((resolver, _) async {
  if (_signingIn case final signingIn?) {
    unawaited(resolver.redirectUntil(const NamedRoute<Object?>('Login')));
    await signingIn.future;
  }
  resolver.next();
});

// Home, Gift, Other and Login; and Store with the tabs Shop, Orders and
// Account, where Orders holds a nested router with OrdersIndex and Order.
// Gift and Order have the sign-in guard.
RootStackRouter _storeRouter() => .build(
  routes: [
    _page('Home', '/'),
    _page('Login', '/login'),
    NamedRouteDef(
      name: 'Gift',
      path: '/gift',
      guards: [_signInGuard],
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
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  tearDown(() => _signingIn = null);

  // The user signs in on Login, and the guard that waits lets its page in.
  Future<void> signIn(WidgetTester tester) async {
    _signingIn?.complete();
    _signingIn = null;
    await settleBrowser(tester);
  }

  // Steps: on Home, push Gift and then Other. Press the back button two
  // times, onto Home, and sign out. Press the forward button, and Login
  // shows on the entry of Gift. Sign in, then press the forward button.
  testWidgets('Forward onto Gift, whose guard shows Login, ends on the entry '
      'of Gift and keeps the entry of Other ahead', (tester) async {
    final router = _storeRouter();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    String shown() =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
    for (final path in ['/gift', '/other']) {
      unawaited(router.pushPath<Object?>(path));
      await settleBrowser(tester);
    }
    await pressBrowserBack(tester);
    await pressBrowserBack(tester);
    expect(shown(), 'Home / 0');
    _signingIn = Completer<void>();

    await pressBrowserForward(tester);
    expect(shown(), 'Login /login 1');
    await signIn(tester);
    expect(shown(), 'Gift /gift 1');

    await pressBrowserForward(tester);
    expect(shown(), 'Other /other 2');
  });

  // Steps: on Home, open Store on Orders, then Order 7 in Orders, then the
  // Account tab. Press the back button two times, onto OrdersIndex, and sign
  // out. Press the forward button: Login shows on the entry of Order 7. Sign
  // in, press the forward button, then the back button until Home.
  testWidgets('In Store, forward onto Order 7, whose guard shows Login, ends '
      'on the entry of Order 7 and keeps the entry of Account ahead', (
    tester,
  ) async {
    final router = _storeRouter();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    String shown() =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
    unawaited(router.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('Store')!;
    unawaited(
      tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'),
    );
    await settleBrowser(tester);
    tabs.setActiveIndex(2);
    await settleBrowser(tester);
    await pressBrowserBack(tester);
    await pressBrowserBack(tester);
    expect(shown(), 'OrdersIndex /store/orders 1');
    _signingIn = Completer<void>();

    await pressBrowserForward(tester);
    expect(shown(), 'Login /login 2');
    await signIn(tester);
    expect(shown(), 'Order /store/orders/7 2');

    await pressBrowserForward(tester);
    expect(shown(), 'Account /store/account 3');
    final backWalk = <String>[];
    for (var i = 0; i < 4 && browserSerialCount > home; i++) {
      await pressBrowserBack(tester);
      backWalk.add(shown());
    }
    expect(backWalk, [
      'Order /store/orders/7 2',
      'OrdersIndex /store/orders 1',
      'Home / 0',
    ]);
  });
}
