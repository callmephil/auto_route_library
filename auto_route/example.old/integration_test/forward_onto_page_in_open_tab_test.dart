import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, the forward button onto the entry of a page in the tab on
// screen changes no entry (callmephil/auto_route_library#54).
// Headless tests: auto_route/test/forward_onto_page_in_open_tab_test.dart
// and auto_route/test/web/forward_onto_page_in_open_tab_web_test.dart.
//
// The reload is made the way the headless test makes it: the app is taken
// down and a new one starts on the same browser history. A real reload under
// flutter drive would restart the page that runs the tests.
//
// Native behavior this holds to: the HTML standard's session history, where
// a forward traversal goes to the next entry and adds or changes none. Web
// only: off the web there is no browser history to walk.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('forward onto a page in the tab on screen', () {
    // Steps: on Home, open Store on its Orders tab, open Order 7 and Order
    // 8 there, then push A. Press back once and reload on Order 8. Press
    // back three times, then forward four times.
    // Was: forward onto the entry of Order 7 stepped back and pushed
    // /store/orders/7, so the entries of Order 8 and A were gone.
    // Should: each press moves one entry, and the last one shows A.
    testWidgets(
      'forward walks to A after a reload on Order 8',
      (tester) async {
        // The app before the reload, and the app after it.
        final [first, router] = [for (var i = 0; i < 2; i++) _storeRouter()];
        await pumpRouterConfigApp(
          tester,
          first.config(
            // Opens at '/', whatever url the test before left.
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;
        unawaited(first.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        await _openOrder(tester, first, '7');
        await _openOrder(tester, first, '8');
        unawaited(first.push(const NamedRoute<Object?>('ARoute')));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 4);
        await expectBrowserEntryAfter(-1, pressBrowserBack);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        first.dispose();

        // The reload. The route information provider reads the url the app
        // opens at when the config is made, so the url is set first.
        addTearDown(router.dispose);
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/store/orders/8';
        final config = router.config();
        await pumpAppAtDeepLink(
          tester,
          '/store/orders/8',
          MaterialApp.router(routerConfig: config),
        );
        expect(router.topRoute.name, 'OrderRoute');

        const underStore = ['HomeRoute', 'StoreRoute'];
        await _expectWalk(tester, router, [
          (-1, 'OrderRoute', '/store/orders/7', ['StoreRoute']),
          (-1, 'OrdersIndexRoute', '/store/orders', ['StoreRoute']),
          (-1, 'HomeRoute', '/', ['HomeRoute']),
          (1, 'OrdersIndexRoute', '/store/orders', underStore),
          (1, 'OrderRoute', '/store/orders/7', underStore),
          (1, 'OrderRoute', '/store/orders/8', underStore),
          (1, 'ARoute', '/a', [...underStore, 'ARoute']),
        ]);
        await tester.pumpWidget(const SizedBox());
      },
      skip: !kIsWeb,
    );

    // Steps: with rebuildStackOnDeepLink, on Home, open Store on its Orders
    // tab and Order 7 there, type /store/orders/8, push A, press back four
    // times, then forward four times.
    // Was: forward onto the entry of Order 8 stepped back and pushed
    // /store/orders/8, so the last forward press found no entry of A.
    // Should: each press moves one entry, and the last one shows A.
    testWidgets(
      'forward walks to A after a typed url to Order 8',
      (tester) async {
        final router = _storeRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            // Opens at '/', whatever url the test before left.
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;
        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        await _openOrder(tester, router, '7');
        typeBrowserUrl('/store/orders/8');
        await expectBrowserEntry(home + 3);
        await tester.pumpAndSettle();
        unawaited(router.push(const NamedRoute<Object?>('ARoute')));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 4);

        const underStore = ['HomeRoute', 'StoreRoute'];
        await _expectWalk(tester, router, [
          (-1, 'OrderRoute', '/store/orders/8', ['StoreRoute']),
          (-1, 'OrderRoute', '/store/orders/7', ['StoreRoute']),
          (-1, 'OrdersIndexRoute', '/store/orders', ['StoreRoute']),
          (-1, 'HomeRoute', '/', ['HomeRoute']),
          (1, 'OrdersIndexRoute', '/store/orders', underStore),
          (1, 'OrderRoute', '/store/orders/7', underStore),
          (1, 'OrderRoute', '/store/orders/8', underStore),
          (1, 'ARoute', '/a', [...underStore, 'ARoute']),
        ]);
      },
      skip: !kIsWeb,
    );
  });
}

// Presses back for a step of -1 and forward for 1, and expects after each
// press the page on top, its url and the pages of the root stack.
Future<void> _expectWalk(
  WidgetTester tester,
  RootStackRouter router,
  List<(int, String, String, List<String>)> walk,
) async {
  for (final (step, name, url, stack) in walk) {
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
      reason: 'the pages at $url',
    );
  }
}

// Opens Order [id] in the Orders tab of [router].
Future<void> _openOrder(
  WidgetTester tester,
  RootStackRouter router,
  String id,
) async {
  final tabs = router.innerRouterOf<TabsRouter>('StoreRoute')!;
  unawaited(
    tabs.innerRouterOf<StackRouter>('OrdersTab')!.pushPath<Object?>(id),
  );
  await tester.pumpAndSettle();
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, A, then Store with the tabs Shop and Orders. Orders holds a nested
// router with OrdersIndex and Order.
RootStackRouter _storeRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('ARoute', '/a'),
    NamedRouteDef(
      name: 'StoreRoute',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('ShopTab'),
            NamedRoute<Object?>('OrdersTab'),
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
      ],
    ),
  ],
);
