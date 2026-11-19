import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link to a page in a tab whose guard waits, when that page has a guard
// of its own, opens the page once and asks its guard once. On the web the
// link keeps the one browser entry the browser made for it. Before, the
// nested router of the tab opened the page from the tab's page, and the
// tab change opened it again: the page was on the stack two times, its
// guard was asked two times, and on the web the link got a second entry.
// After a "no" of that guard, the first tab stayed on screen
// (callmephil/auto_route_library#33).
// Headless tests:
// auto_route/test/link_to_guarded_page_in_waiting_tab_test.dart and
// auto_route/test/web/link_to_guarded_page_in_waiting_tab_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator holds each page once.
// Android's conditional navigation pops back from a destination whose check
// fails. On the web, the HTML standard's session history: the browser makes
// one entry for a url it opens.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a link to a guarded page in a tab whose guard waits', () {
    // Opens the app of [router] at /store/orders/7 as the platform opens
    // it, with the link's page alone, as on the web. Answers the browser
    // entry of the link.
    Future<int> open(WidgetTester tester, RootStackRouter router) async {
      final linkEntry = browserEntryIndex() ?? 0;
      // The config reads the platform's initial route when it is first
      // made, so it is made inside the app, after pumpAppAtDeepLink sets
      // the link, as runApp would find it.
      await pumpAppAtDeepLink(
        tester,
        '/store/orders/7',
        Builder(
          builder: (_) => MaterialApp.router(
            routerConfig: router.config(includePrefixMatches: false),
          ),
        ),
      );
      return linkEntry;
    }

    // Steps: open the app at /store/orders/7. The guard of the tab Orders
    // waits 1 ms. The guard of Order waits 1 ms, or answers at once.
    // Was: Order 7 two times, with a guard that waits, and its guard asked
    // two times. On the web, a second entry.
    // Should: Order 7 once, its guard asked once, and one entry.
    for (final orderWaits in [true, false]) {
      testWidgets(
        'Opened at /store/orders/7: Order 7 opens once, and its guard is '
        'asked once${orderWaits ? ', with a guard of Order that waits' : ''}',
        (tester) async {
          var orderAsks = 0;
          final router = _storeRouter(
            orderWaits: orderWaits,
            allowsOrder: true,
            onOrderAsk: () => orderAsks++,
          );
          final linkEntry = await open(tester, router);

          expect((_orders(router), orderAsks), ('OrderRoute 7', 1));
          expect(find.text('Order 7'), findsOneWidget);
          await expectBrowserUrl('/store/orders/7');
          await expectAppWroteDeepLinkEntry(linkEntry);
        },
      );
    }

    // Steps: as above, but the guard of Order says no.
    // Was: the tab Shop stayed on screen, at /store/shop.
    // Should: the tab Orders shows its first page at /store/orders, on the
    // one entry, as when the tab guard answers at once.
    testWidgets(
      'Opened at /store/orders/7, the guard of Order says no: the tab Orders '
      'shows its first page',
      (tester) async {
        var orderAsks = 0;
        final router = _storeRouter(
          orderWaits: true,
          allowsOrder: false,
          onOrderAsk: () => orderAsks++,
        );
        final linkEntry = await open(tester, router);

        expect((_orders(router), orderAsks), ('OrdersIndexRoute', 1));
        expect(find.text('OrdersIndexRoute'), findsOneWidget);
        await expectBrowserUrl('/store/orders');
        await expectAppWroteDeepLinkEntry(linkEntry);
      },
    );

    // Steps: on Home, call navigatePath to /store/orders/7. The guard of
    // Order says no.
    // Was: the tabs page stayed over Home on the tab Shop, and onFailure
    // heard nothing.
    // Should: Home stays at '/', and onFailure hears the rejection once.
    testWidgets(
      'navigatePath from Home, the guard of Order says no: Home stays, and '
      'onFailure hears the rejection',
      (tester) async {
        final router = _storeRouter(orderWaits: true, allowsOrder: false);
        // At '/', whatever url the test before left in the browser.
        await pumpRouterAppWithConfig(tester, router);

        final failures = <NavigationFailure>[];
        unawaited(
          router.navigatePath('/store/orders/7', onFailure: failures.add),
        );
        await tester.pumpAndSettle();

        expect(
          (router.topRoute.name, router.stack.length, failures.length),
          ('HomeRoute', 1, 1),
        );
        expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
        await expectBrowserUrl('/');
      },
    );
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// The app of the issue: Home, then Store with the tabs Shop, Orders and
// Account. Orders holds a nested router with OrdersIndex and Order, and a
// guard that waits 1 ms, then lets the tab in. Order has a guard of its
// own, which waits 1 ms when [orderWaits] and answers at once otherwise. It
// calls [onOrderAsk], when given, each time it is asked, and lets the page
// in when [allowsOrder].
RootStackRouter _storeRouter({
  required bool orderWaits,
  required bool allowsOrder,
  VoidCallback? onOrderAsk,
}) => .build(
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
          guards: [
            // A sign-in check that waits, as for a token in storage.
            AutoRouteGuard.simple((resolver, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndexRoute', ''),
            NamedRouteDef(
              name: 'OrderRoute',
              path: ':id',
              guards: [
                // A check of the order's own, such as for its owner.
                AutoRouteGuard.simple((resolver, _) async {
                  onOrderAsk?.call();
                  if (orderWaits) {
                    await Future<void>.delayed(const Duration(milliseconds: 1));
                  }
                  if (allowsOrder) {
                    resolver.next();
                  } else {
                    resolver.reject();
                  }
                }),
              ],
              builder: (_, data) =>
                  Text('Order ${data.params.getString('id')}'),
            ),
          ],
        ),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);

// The pages of the nested router of the tab Orders of [router], with the id
// of each Order.
String _orders(RootStackRouter router) {
  final pages =
      router
          .innerRouterOf<TabsRouter>('StoreRoute')
          ?.innerRouterOf<StackRouter>('OrdersTab')
          ?.stack ??
      const <AutoRoutePage<Object?>>[];
  return pages
      .map(
        (page) => [
          page.routeData.name,
          ?page.routeData.params.optString('id'),
        ].join(' '),
      )
      .join(', ');
}
