import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, after a link replaces the stack, the app's next push adds one
// entry, and forward presses change no entry
// (callmephil/auto_route_library#51).
// Headless tests: auto_route/test/rebuild_stack_push_after_link_test.dart
// and auto_route/test/web/rebuild_stack_push_after_link_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// history.pushState adds one entry after the current one and a back or
// forward traversal adds or changes none. Web only: off the web there is no
// address bar to type a url into.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a push after a link that replaced the stack', () {
    // Steps: with rebuildStackOnDeepLink and prefix matches, on Home, push
    // A, type /b into the address bar, then push C and press back.
    // Was: the app wrote / over the entry of /b and pushed /b and /c, two
    // entries for one push.
    // Should: C gets one entry after the entry of /b, and back shows B.
    testWidgets(
      'C gets one entry after the entry of /b',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            includePrefixMatches: true,
            // Opens at '/', whatever url the test before left.
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;
        unawaited(router.push(const NamedRoute<Object?>('ARoute')));
        await tester.pumpAndSettle();
        typeBrowserUrl('/b');
        await expectBrowserEntry(home + 2);
        await tester.pumpAndSettle();

        unawaited(router.push(const NamedRoute<Object?>('CRoute')));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 3);
        await expectBrowserUrl('/c');

        await expectBrowserEntryAfter(-1, pressBrowserBack);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/b');
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'BRoute',
        ]);
      },
      skip: !kIsWeb,
    );

    // Steps: with rebuildStackOnDeepLink, on Home, open Store on its Orders
    // tab, type /store/account, push A, press back three times, then
    // forward three times.
    // Was: forward onto the entry of Account stepped back and pushed
    // /store/account, so the third forward press found no entry of A.
    // Should: each press moves one entry, and the last one shows A.
    testWidgets(
      'forward walks back to A after a typed url to Account',
      (tester) async {
        final router = _storeRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;
        unawaited(router.pushPath<Object?>('/store/orders'));
        await tester.pumpAndSettle();
        typeBrowserUrl('/store/account');
        await expectBrowserEntry(home + 2);
        await tester.pumpAndSettle();
        unawaited(router.push(const NamedRoute<Object?>('ARoute')));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 3);

        const underStore = ['HomeRoute', 'StoreRoute'];
        for (final (step, name, url, stack) in [
          (-1, 'AccountTab', '/store/account', ['StoreRoute']),
          (-1, 'OrdersTab', '/store/orders', ['StoreRoute']),
          (-1, 'HomeRoute', '/', ['HomeRoute']),
          (1, 'OrdersTab', '/store/orders', underStore),
          (1, 'AccountTab', '/store/account', underStore),
          (1, 'ARoute', '/a', [...underStore, 'ARoute']),
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
            reason: 'the pages at $url',
          );
        }
      },
      skip: !kIsWeb,
    );
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, A, then Store with the tabs Shop, Orders and Account.
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
            NamedRoute<Object?>('AccountTab'),
          ],
        ),
      ),
      children: [
        _page('ShopTab', 'shop'),
        _page('OrdersTab', 'orders'),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);
