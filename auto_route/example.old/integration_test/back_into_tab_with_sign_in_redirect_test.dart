import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, a back press onto a page in a tab not on screen, whose guard
// shows a sign-in page with redirectUntil, writes the sign-in page over the
// entry the browser goes to, and the page takes the entry back after the
// sign-in. Before, the app stepped the browser forward one entry and pushed
// the sign-in page after the entry of the tab on screen, which then stood
// under it (callmephil/auto_route_library#44).
// Headless tests: auto_route/test/back_into_tab_with_sign_in_redirect_test.dart
// and auto_route/test/web/back_into_tab_with_sign_in_redirect_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where a traversal adds and changes no entry and history.replaceState
// writes over the current entry; and Flutter's Navigator.pushReplacement,
// which puts a route in the place of another. Web only: off the web there
// is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back onto a page in a tab whose guard shows a sign-in page', () {
    tearDown(() => _signingIn = null);

    // Steps: on Home, open Store on Orders, Order 7 in Orders, then the
    // Account tab. Sign out and press the browser's back button: Login
    // shows on the entry of Order 7. Sign in, then press back until Home
    // and forward until Account.
    // Was: Login went on a new entry after the entry of Account, and back
    // after the sign-in showed Account first.
    // Should: Order 7 on its entry, back shows OrdersIndex and Home, and
    // forward walks the same entries up to Account.
    testWidgets(
      'Back onto Order 7 ends on its entry and keeps the entry of Account',
      (tester) async {
        final (router, home) = await _openAccountAfterOrder(tester);
        _signingIn = Completer<void>();

        await _expectBack(tester, router, ('LoginRoute', '/login'));
        _signingIn?.complete();
        _signingIn = null;
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 2);
        await expectBrowserUrl('/store/orders/7');
        expect(router.topRoute.name, 'OrderRoute');

        await expectBrowserBackWalk(tester, router, [
          ('OrdersIndexRoute', '/store/orders'),
          ('HomeRoute', '/'),
        ]);
        for (final page in [
          ('OrdersIndexRoute', '/store/orders'),
          ('OrderRoute', '/store/orders/7'),
          ('AccountTab', '/store/account'),
        ]) {
          final (name, url) = page;
          await expectBrowserEntryAfter(1, pressBrowserForward);
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(router.topRoute.name, name, reason: 'after forward to $url');
        }
      },
      skip: !kIsWeb,
    );

    // Steps: the steps above up to Login, then press back again.
    // Was: the browser went to the entry of Account, where the user started.
    // Should: the browser goes to the entry of OrdersIndex.
    testWidgets(
      'A second back press on Login goes to the entry of OrdersIndex',
      (tester) async {
        final (router, home) = await _openAccountAfterOrder(tester);
        _signingIn = Completer<void>();
        await _expectBack(tester, router, ('LoginRoute', '/login'));

        await expectBrowserEntryAfter(-1, pressBrowserBack);
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
      },
      skip: !kIsWeb,
    );
  });
}

// Completes once the user has signed in; null while signed in.
Completer<void>? _signingIn;

// Opens Store on Orders, Order 7 in Orders, then the Account tab, and
// answers the router and the entry of Home.
Future<(RootStackRouter, int)> _openAccountAfterOrder(
  WidgetTester tester,
) async {
  final router = _storeRouter();
  await pumpRouterConfigApp(tester, router.config());
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
  return (router, home);
}

// Presses the browser's back button and expects [page], a page name and its
// url, on top of [router], on the entry before the one before the press.
Future<void> _expectBack(
  WidgetTester tester,
  RootStackRouter router,
  (String, String) page,
) async {
  final (name, url) = page;
  await expectBrowserEntryAfter(-1, pressBrowserBack);
  await tester.pumpAndSettle();
  await expectBrowserUrl(url);
  expect(router.topRoute.name, name, reason: 'after back to $url');
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home and Login; and Store with the tabs Shop, Orders and Account, where
// Orders holds a nested router with OrdersIndex and Order. While the user
// is signed out, the guard of Orders shows Login and waits for the sign-in.
RootStackRouter _storeRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('LoginRoute', '/login'),
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
            AutoRouteGuard.simple((resolver, _) async {
              if (_signingIn case final signingIn?) {
                unawaited(
                  resolver.redirectUntil(
                    const NamedRoute<Object?>('LoginRoute'),
                  ),
                );
                await signingIn.future;
              }
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndexRoute', ''),
            _page('OrderRoute', ':id'),
          ],
        ),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);
