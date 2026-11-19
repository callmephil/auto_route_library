import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a press of the browser's back or forward button to an entry
// whose page is still open asks no guard of the open pages on the way.
// Before, the app opened the entry as a link to its routes, and each stack
// put the open page it reached again on anew, through its guards: the
// back press into another tab asked the guards of the tabs page and of the
// page open in that tab again, and the back press from a page pushed over
// Mail asked those of Mail and of its open message again
// (callmephil/auto_route_library#36).
// Headless tests:
// auto_route/test/browser_back_to_open_page_asks_no_guard_test.dart and
// auto_route/test/web/browser_back_to_open_page_asks_no_guard_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal shows the page the user saw at the entry, and Flutter's
// Navigator.pop, which asks nothing of the route under it. Web only: off the
// web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('the browser back button to an open page', () {
    // Steps: on Home, open Store on its Orders tab, whose guard waits 1 ms.
    // Open Order 7 in Orders, then select the Account tab. Press the
    // browser's back button, then its forward button, back twice, and
    // forward again.
    // Was: each press asked the global guard and the own guard of Store
    // again, and the back press into Orders those of Order 7 too.
    // Should: the back press into Orders asks only the guard of the tab. The
    // press forward to Account asks no guard. The forward press onto Order 7,
    // which the back walk closed, asks its guards as before.
    testWidgets(
      'Back into another tab asks only the guard of the tab',
      (tester) async {
        final asked = <String>[];
        final router = _router(asked);
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('StoreRoute')!;
        unawaited(
          tabs.innerRouterOf<StackRouter>('OrdersTab')!.pushPath<Object?>('7'),
        );
        await tester.pumpAndSettle();
        tabs.setActiveIndex(2);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/store/account');

        for (final (press, change, name, url, guards) in [
          (pressBrowserBack, -1, 'OrderRoute', '/store/orders/7', 'OrdersTab'),
          (
            pressBrowserForward,
            1,
            'AccountTab',
            '/store/account',
            'no guard',
          ),
          (pressBrowserBack, -1, 'OrderRoute', '/store/orders/7', 'OrdersTab'),
          (
            pressBrowserBack,
            -1,
            'OrdersIndexRoute',
            '/store/orders',
            'no guard',
          ),
          (
            pressBrowserForward,
            1,
            'OrderRoute',
            '/store/orders/7',
            'global OrderRoute, OrderRoute',
          ),
        ]) {
          asked.clear();
          await expectBrowserEntryAfter(change, press);
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(
            (
              router.topRoute.name,
              asked.isEmpty ? 'no guard' : asked.join(', '),
            ),
            (name, guards),
            reason: 'after the press to $url',
          );
        }
      },
      skip: !kIsWeb,
    );

    // Steps: on Home, open message 77 in Mail, then push Settings. Press the
    // browser's back button.
    // Was: the press asked the global guard and the own guards of Mail and
    // of the message again.
    // Should: the message shows, and no guard is asked.
    testWidgets(
      'Back from a page pushed over Mail asks no guard',
      (tester) async {
        final asked = <String>[];
        final router = _router(asked);
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.navigatePath('/mail/77'));
        await tester.pumpAndSettle();
        unawaited(router.push(const NamedRoute('SettingsRoute')));
        await tester.pumpAndSettle();
        await expectBrowserUrl('/settings');
        asked.clear();

        await expectBrowserEntryAfter(-1, pressBrowserBack);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/mail/77');

        expect(
          (router.topRoute.name, asked.isEmpty ? 'no guard' : asked.join(', ')),
          ('MessageRoute', 'no guard'),
        );
      },
      skip: !kIsWeb,
    );
  });
}

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
      page('HomeRoute', '/'),
      NamedRouteDef(
        name: 'StoreRoute',
        path: '/store',
        guards: [noting('StoreRoute')],
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
          page('ShopTab', 'shop'),
          NamedRouteDef(
            name: 'OrdersTab',
            path: 'orders',
            guards: [
              // A sign-in check that waits, as for a token in storage.
              AutoRouteGuard.simple((resolver, _) async {
                asked.add('OrdersTab');
                await Future<void>.delayed(const Duration(milliseconds: 1));
                resolver.next();
              }),
            ],
            builder: (_, _) => const AutoRouter(),
            children: [
              page('OrdersIndexRoute', ''),
              page('OrderRoute', ':id', isGuarded: true),
            ],
          ),
          page('AccountTab', 'account'),
        ],
      ),
      NamedRouteDef(
        name: 'MailRoute',
        path: '/mail',
        guards: [noting('MailRoute')],
        builder: (_, _) => const Scaffold(body: AutoRouter()),
        children: [
          page('InboxRoute', ''),
          page('MessageRoute', ':id', isGuarded: true),
        ],
      ),
      page('SettingsRoute', '/settings'),
    ],
  );
}
