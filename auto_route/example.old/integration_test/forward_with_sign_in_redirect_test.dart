import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, a guard that shows a sign-in page with redirectUntil when the
// browser's forward button reaches its page, and lets the page in after the
// sign-in, leaves the browser on the entry the user went to, and the entries
// ahead stay. Before, Login left before the guarded page went on in its
// place, and the url of the page under Login made the browser step back one
// entry and push the guarded page, which dropped the entries ahead
// (callmephil/auto_route_library#37).
// Headless tests: auto_route/test/forward_with_sign_in_redirect_test.dart
// and auto_route/test/web/forward_with_sign_in_redirect_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where a traversal changes no entry and only history.pushState removes the
// entries ahead; and Flutter's Navigator.pushReplacement, which puts a route
// in the place of another in one step. Web only: off the web there is no
// browser forward button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('forward onto a page whose guard shows a sign-in page', () {
    tearDown(() => _signingIn = null);

    // Steps: on Home, push Gift, then Other. Press the browser's back button
    // two times, onto Home, and sign out. Press its forward button: Login
    // shows on the entry of Gift. Sign in, then press the forward button.
    // Was: the browser held the entries of Home and Gift alone after the
    // sign-in, and the forward button had nothing to go to.
    // Should: Gift on its entry, and the forward button then shows Other.
    testWidgets(
      'Forward onto Gift ends on its entry and keeps the entry of Other',
      (tester) async {
        final router = _storeRouter();
        await pumpRouterConfigApp(tester, router.config());
        final home = browserEntryIndex()!;
        for (final path in ['/gift', '/other']) {
          unawaited(router.pushPath<Object?>(path));
          await tester.pumpAndSettle();
        }
        await expectBrowserEntry(home + 2);
        await expectBrowserBackWalk(tester, router, [
          ('GiftRoute', '/gift'),
          ('HomeRoute', '/'),
        ]);
        _signingIn = Completer<void>();

        await _expectForward(tester, router, ('LoginRoute', '/login'));
        await _signIn(tester);
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/gift');
        expect(router.topRoute.name, 'GiftRoute');

        await _expectForward(tester, router, ('OtherRoute', '/other'));
      },
      skip: !kIsWeb,
    );

    // Steps: on Home, open Store on Orders, Order 7 in Orders, then the
    // Account tab. Press the browser's back button two times, onto
    // OrdersIndex, and sign out. Press its forward button: Login shows on
    // the entry of Order 7. Sign in, press the forward button, then the back
    // button until Home.
    // Was: the entry of Account ahead was lost after the sign-in.
    // Should: Order 7 on its entry, forward shows Account, and back then
    // shows Order 7, OrdersIndex and Home.
    testWidgets(
      'In Store, forward onto Order 7 ends on its entry and keeps the entry '
      'of Account',
      (tester) async {
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
        await expectBrowserBackWalk(tester, router, [
          ('OrderRoute', '/store/orders/7'),
          ('OrdersIndexRoute', '/store/orders'),
        ]);
        _signingIn = Completer<void>();

        await _expectForward(tester, router, ('LoginRoute', '/login'));
        await _signIn(tester);
        await expectBrowserEntry(home + 2);
        await expectBrowserUrl('/store/orders/7');
        expect(router.topRoute.name, 'OrderRoute');

        await _expectForward(tester, router, ('AccountTab', '/store/account'));
        await expectBrowserBackWalk(tester, router, [
          ('OrderRoute', '/store/orders/7'),
          ('OrdersIndexRoute', '/store/orders'),
          ('HomeRoute', '/'),
        ]);
      },
      skip: !kIsWeb,
    );
  });
}

// Completes once the user has signed in; null while signed in.
Completer<void>? _signingIn;

// The user signs in on Login, and the guard that waits lets its page in.
Future<void> _signIn(WidgetTester tester) async {
  _signingIn?.complete();
  _signingIn = null;
  await tester.pumpAndSettle();
}

// Presses the browser's forward button and expects [page], a page name and
// its url, on top of [router], on the entry after the one before the press.
Future<void> _expectForward(
  WidgetTester tester,
  RootStackRouter router,
  (String, String) page,
) async {
  final (name, url) = page;
  await expectBrowserEntryAfter(1, pressBrowserForward);
  await tester.pumpAndSettle();
  await expectBrowserUrl(url);
  expect(router.topRoute.name, name, reason: 'after forward to $url');
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// While the user is signed out, shows Login and waits for the sign-in. Then,
// or at once, lets the page in.
final _signInGuard = AutoRouteGuard.simple((resolver, _) async {
  if (_signingIn case final signingIn?) {
    unawaited(resolver.redirectUntil(const NamedRoute<Object?>('LoginRoute')));
    await signingIn.future;
  }
  resolver.next();
});

// Home, Gift, Other and Login; and Store with the tabs Shop, Orders and
// Account, where Orders holds a nested router with OrdersIndex and Order.
// Gift and Order have the sign-in guard.
RootStackRouter _storeRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('LoginRoute', '/login'),
    NamedRouteDef(
      name: 'GiftRoute',
      path: '/gift',
      guards: [_signInGuard],
      builder: (_, _) => const Text('GiftRoute'),
    ),
    _page('OtherRoute', '/other'),
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
              guards: [_signInGuard],
              builder: (_, _) => const Text('OrderRoute'),
            ),
          ],
        ),
        _page('AccountTab', 'account'),
      ],
    ),
  ],
);
