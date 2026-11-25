@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, a sign-out closes a guarded page that a press of the
// back button shows again while the guard of that page decides. The steps,
// what was seen and what should be seen are those of the Order 7 case of
// test/sign_out_during_back_closes_page_test.dart, the headless test.
//
// Native behavior this holds to: a back traversal of the HTML standard's
// session history changes only which entry is current, and Flutter's
// Navigator.pop shows the same route under it. The latest change wins.

// The session that the router asks its guards again for.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  // A slow check of the session, which the guard of Order waits for.
  Completer<void>? check;

  void signOut() {
    isSignedIn = false;
    notifyListeners();
  }
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router(_Session session) => .build(
  routes: [
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
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndex', ''),
            NamedRouteDef(
              name: 'Order',
              path: ':id',
              guards: [
                AutoRouteGuard.simple((resolver, _) async {
                  if (session.check case final check?) await check.future;
                  session.isSignedIn ? resolver.next() : resolver.reject();
                }),
              ],
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

  testWidgets('A sign-out closes Order 7 that a back press shows meanwhile', (
    tester,
  ) async {
    final session = _Session();
    addTearDown(session.dispose);
    final router = _router(session);
    await pumpRouterConfigApp(
      tester,
      router.config(reevaluateListenable: session),
    );
    await settleBrowser(tester);
    unawaited(router.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('Store')!;
    final orders = tabs.innerRouterOf<StackRouter>('Orders')!;
    unawaited(orders.pushPath<Object?>('7'));
    await settleBrowser(tester);
    tabs.setActiveIndex(2);
    await settleBrowser(tester);
    expect(browserPath, '/store/account');

    final check = Completer<void>();
    session
      ..check = check
      ..signOut();
    await tester.pumpAndSettle();
    await pressBrowserBack(tester);
    expect((browserPath, router.topRoute.name), ('/store/orders/7', 'Order'));
    check.complete();
    await settleBrowser(tester);

    expect(tester.takeException(), isNull);
    expect(
      (
        browserPath,
        orders.stack.map((page) => page.routeData.name).join(', '),
        find.text('Order').evaluate().length,
      ),
      ('/store/orders', 'OrdersIndex', 0),
    );
  });
}
