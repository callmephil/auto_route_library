import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a sign-out closes a guarded page that a press of the browser's
// back button shows again while the guard of that page decides. Before, the
// press put a new page in place of the open one, and the guard's no was
// dropped as too late. Headless tests:
// auto_route/test/sign_out_during_back_closes_page_test.dart and
// auto_route/test/web/sign_out_during_back_closes_page_web_test.dart.
//
// Native behavior this holds to: a back traversal of the HTML standard's
// session history changes only which entry is current, and Flutter's
// Navigator.pop shows the same route under it. The latest change wins. Web
// only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a sign-out while a back press shows a guarded page', () {
    tearDown(() => _check = null);

    // Steps: on Home, open Store on Orders, Order 7 in Orders, then the
    // Account tab. The session check gets slow, and the user signs out.
    // Press the browser's back button into Orders, then the check ends.
    // Was: Order 7 stayed on screen for the signed-out user.
    // Should: the guard's no closes Order 7, and OrdersIndex shows.
    testWidgets(
      'A sign-out closes Order 7 that a back press shows meanwhile',
      (tester) async {
        // Whether the user is signed in.
        final session = ValueNotifier(true);
        addTearDown(session.dispose);
        final router = _storeRouter(session);
        await pumpRouterConfigApp(
          tester,
          router.config(
            reevaluateListenable: session,
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('StoreRoute')!;
        final orders = tabs.innerRouterOf<StackRouter>('OrdersTab')!;
        unawaited(orders.pushPath<Object?>('7'));
        await tester.pumpAndSettle();
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/store/account');

        final check = Completer<void>();
        _check = check;
        session.value = false;
        await tester.pumpAndSettle();
        await expectBrowserEntryAfter(-1, pressBrowserBack);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/store/orders/7');
        expect(router.topRoute.name, 'OrderRoute');
        check.complete();
        await tester.pumpAndSettle();

        await expectBrowserUrl('/store/orders');
        expect(
          (
            orders.stack.map((page) => page.routeData.name).join(', '),
            find.text('OrderRoute').evaluate().length,
          ),
          ('OrdersIndexRoute', 0),
        );
      },
      skip: !kIsWeb,
    );
  });
}

// A slow check of the session, which the guard of Order waits for.
Completer<void>? _check;

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, and Store with the tabs Shop, Orders and Account. Orders holds a
// nested router with OrdersIndex and Order, whose guard lets the user in
// only while [isSignedIn] holds true, once the check ends.
RootStackRouter _storeRouter(ValueListenable<bool> isSignedIn) => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'StoreRoute',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('ShopTab'),
            NamedRoute<Object?>('OrdersTab'),
            NamedRoute<Object?>('AccountTab'),
          ],
        ),
      ),
      children: [
        _page('ShopTab', 'shop'),
        NamedRouteDef(
          name: 'OrdersTab',
          path: 'orders',
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndexRoute', ''),
            NamedRouteDef(
              name: 'OrderRoute',
              path: ':id',
              guards: [
                AutoRouteGuard.simple((resolver, _) async {
                  if (_check case final check?) await check.future;
                  isSignedIn.value ? resolver.next() : resolver.reject();
                }),
              ],
              builder: (_, _) => const Text('OrderRoute'),
            ),
          ],
        ),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);
