import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, with rebuildStackOnDeepLink, the browser's back and forward
// buttons go through each page once and change no entry. Before, the app
// opened the entry the browser went to as a link that rebuilds the stack:
// Home and the pages under the entry's page closed, the url of that page
// was written over the entry of Home, and back stopped before Home
// (callmephil/auto_route_library#38).
// Headless tests:
// auto_route/test/rebuild_stack_back_and_forward_test.dart and
// auto_route/test/web/rebuild_stack_back_and_forward_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where a back or forward traversal moves to another entry and adds or
// changes none. Web only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back and forward with rebuildStackOnDeepLink', () {
    // Steps: with rebuildStackOnDeepLink, on Home, open Store on its Orders
    // tab, open Order 7 in Orders, then select the Account tab. Press the
    // browser's back button until Home, then its forward button until
    // Account.
    // Was: back showed Order 7, then Orders, then stopped: Home was lost.
    // Should: back shows Order 7, Orders, then Home, one entry each, and
    // forward walks the same entries up to Account, with Home under them.
    testWidgets(
      'Back shows Order 7, Orders, then Home',
      (tester) async {
        final router = _storeRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            // Opens at '/', as the browser's url carries over from the test
            // before; later links, such as the browser's steps, go through.
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;

        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('StoreRoute')!;
        unawaited(
          tabs.innerRouterOf<StackRouter>('OrdersTab')!.pushPath<Object?>('7'),
        );
        await tester.pumpAndSettle();
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 3);
        await expectBrowserUrl('/store/account');

        const underStore = ['HomeRoute', 'StoreRoute'];
        for (final (step, name, url, stack) in [
          (-1, 'OrderRoute', '/store/orders/7', underStore),
          (-1, 'OrdersIndexRoute', '/store/orders', underStore),
          (-1, 'HomeRoute', '/', ['HomeRoute']),
          (1, 'OrdersIndexRoute', '/store/orders', underStore),
          (1, 'OrderRoute', '/store/orders/7', underStore),
          (1, 'AccountTab', '/store/account', underStore),
        ]) {
          await expectBrowserEntryAfter(
            step,
            step < 0 ? pressBrowserBack : pressBrowserForward,
          );
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(router.topRoute.name, name, reason: 'the page at $url');
          expect(
            router.stack.map((page) => page.name),
            stack,
            reason: 'the pages under the page at $url',
          );
        }
      },
      skip: !kIsWeb,
    );
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account. Orders holds a
// nested router with OrdersIndex and Order.
RootStackRouter _storeRouter() => .build(
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
          children: [_page('OrdersIndexRoute', ''), _page('OrderRoute', ':id')],
        ),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);
