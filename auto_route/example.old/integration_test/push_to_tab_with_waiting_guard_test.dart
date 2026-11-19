import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// A navigation to a tab whose guard waits gives the tabs page one entry,
// also when the tabs build the tab's nested router before the tab shows.
// Before, the nested router of the tab reported the url of the first tab,
// shown while the guard decided, and used up the mark that makes the tab
// take the first tab's place. So the first tab got an entry of its own, and
// back showed it (callmephil/auto_route_library#34).
// Headless tests: auto_route/test/push_to_tab_with_waiting_guard_test.dart
// and auto_route/test/web/push_to_tab_with_waiting_guard_web_test.dart.
//
// Native behavior this holds to: one navigation adds one step back, as
// each call of Android's NavController.navigate pushes one destination and
// Flutter's Navigator.push one route. The tab that the guard lets in takes
// the place of the tab shown meanwhile, as Navigator.pushReplacement puts
// a route in the place of the route on top, and as history.replaceState
// writes over the current entry of the browser (HTML standard).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pushPath to a tab whose guard waits', () {
    for (final tabs in _tabsKinds) {
      // Steps: on Home, push the path /store/orders. Store opens on Shop
      // while the guard of Orders waits 1 ms, then lets the tab in. Go back.
      // Was: back showed Shop, on an entry of its own.
      // Should: back shows Home.
      testWidgets(
        'gives the tabs page one entry, with the ${tabs.name}',
        (tester) async {
          final router = _storeRouter(tabs);
          await pumpRouterAppWithConfig(tester, router);
          final home = browserEntryIndex();

          unawaited(router.pushPath<Object?>('/store/orders'));
          await tester.pumpAndSettle();
          expect(router.topRoute.name, 'OrdersIndexRoute');
          await expectBrowserUrl('/store/orders');
          if (home != null) await expectBrowserEntry(home + 1);

          await _expectBack(tester, router, ('HomeRoute', '/'));
        },
      );

      // With the guard of the app, the no inside Orders takes Store back
      // instead: see the test after this loop.
      if (tabs.hasAppGuard) continue;

      // Steps: the same, with a guard in the nested router of Orders that
      // says no. The tabs page stays on Shop. Select the Account tab, then
      // go back.
      // Was: the tab change took the place of the entry of Shop, and back
      // showed Home.
      // Should: back shows Shop.
      testWidgets(
        'after a no inside the tab, back from the next tab shows Shop, with '
        'the ${tabs.name}',
        (tester) async {
          final router = _storeRouter(tabs, refusesIndex: true);
          await pumpRouterAppWithConfig(tester, router);

          unawaited(router.pushPath<Object?>('/store/orders'));
          await tester.pumpAndSettle();
          expect(router.topRoute.name, 'ShopTab');
          await expectBrowserEntryAfter(1, () async {
            router.innerRouterOf<TabsRouter>('StoreRoute')!.setActiveIndex(2);
            await tester.pumpAndSettle();
          });
          await expectBrowserUrl('/store/account');

          await _expectBack(tester, router, ('ShopTab', '/store/shop'));
        },
      );
    }

    // Steps: with the default tabs and a guard of the app, push the path
    // /store/orders, with a guard in the nested router of Orders that says
    // no.
    // Should: Orders shows as soon as its own guard lets it in, and the no
    // takes the new tabs page back, as a nested guard's no does
    // (callmephil/auto_route_library#33).
    testWidgets(
      'with the default tabs and a guard of the app, a no inside the tab '
      'takes the tabs page back',
      (tester) async {
        final router = _storeRouter(_appGuardTabs, refusesIndex: true);
        await pumpRouterAppWithConfig(tester, router);

        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();

        expect(router.topRoute.name, 'HomeRoute');
        expect(router.stack.length, 1);
        await expectBrowserUrl('/');
      },
    );
  });
}

// Goes back one step, with the browser's back button on the web and with
// the app's own back() off it, and expects [page], a name and a url.
Future<void> _expectBack(
  WidgetTester tester,
  RootStackRouter router,
  (String, String) page,
) async {
  if (kIsWeb) {
    await expectBrowserBackWalk(tester, router, [page]);
    return;
  }
  router.back();
  await tester.pumpAndSettle();
  final (name, url) = page;
  expect((router.topRoute.name, router.currentUrl), (name, url));
}

const _kTabRoutes = [
  NamedRoute<Object?>('ShopTab'),
  NamedRoute<Object?>('OrdersTab'),
  NamedRoute<Object?>('AccountTab'),
];

// A way the tabs page builds its tabs, by its [name]: the tabs [page], and
// whether the app has a guard.
typedef _TabsKind = ({String name, bool hasAppGuard, Widget Function() page});

// How the tabs page builds its tabs. Each way builds the nested router of
// Orders before the tab shows: every tab at once in an IndexedStack, a page
// view that loads every tab at once, or the default tabs off the screen, to
// ask the guard of the app there.
final List<_TabsKind> _tabsKinds = [
  (
    name: 'builder of AutoTabsRouter',
    hasAppGuard: false,
    page: () => AutoTabsRouter.builder(
      routes: _kTabRoutes,
      builder: (_, children, tabsRouter) =>
          IndexedStack(index: tabsRouter.activeIndex, children: children),
    ),
  ),
  (
    name: 'page view that loads every tab',
    hasAppGuard: false,
    page: () =>
        const AutoTabsRouter.pageView(routes: _kTabRoutes, lazyLoad: false),
  ),
  _appGuardTabs,
];

// The default tabs, built off the screen to ask the guard of the app.
final _TabsKind _appGuardTabs = (
  name: 'default tabs and a guard of the app',
  hasAppGuard: true,
  page: () => const AutoTabsRouter(routes: _kTabRoutes),
);

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Store with the tabs Shop, Orders and Account, built as [tabs]
// says. Orders has a guard that waits 1 ms, then lets the tab in, and a
// nested router with OrdersIndex, whose guard says no with [refusesIndex].
RootStackRouter _storeRouter(_TabsKind tabs, {bool refusesIndex = false}) =>
    .build(
      guards: [
        if (tabs.hasAppGuard)
          AutoRouteGuard.simple((resolver, _) => resolver.next()),
      ],
      routes: [
        _page('HomeRoute', '/'),
        NamedRouteDef(
          name: 'StoreRoute',
          path: '/store',
          builder: (_, _) => Scaffold(body: tabs.page()),
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
                NamedRouteDef(
                  name: 'OrdersIndexRoute',
                  path: '',
                  guards: [
                    if (refusesIndex)
                      AutoRouteGuard.simple((resolver, _) => resolver.reject()),
                  ],
                  builder: (_, _) => const Text('OrdersIndexRoute'),
                ),
              ],
            ),
            _page('AccountTab', 'account'),
          ],
        ),
      ],
    );
