import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../named_page.dart';
import '../router_test_utils.dart';

// Leaving a nested router while a guard's redirect was open in it threw "A
// NestedStackRouter was used after being disposed" in debug builds. In
// release builds nothing threw, but the url stayed marked to replace its
// history entry, so the next page opened took the entry of the page before
// it and one step back skipped that page.
// Setup: ShopRoute holds a nested router with ItemsRoute, LoginRoute and
// CartRoute, whose guard calls resolver.redirectUntil(LoginRoute).
// Steps: open Home, push ShopRoute, push CartRoute in its router, so the
// guard shows LoginRoute. Then leave the shop from the root router with
// replaceAll([OtherRoute]), as a sign-out or a "cancel" does, and push
// HomeRoute.
// Native behavior this holds to: Flutter disposes a route's Navigator with
// its routes, and nothing is taken off a disposed Navigator; a
// ChangeNotifier is not used after dispose. On iOS and Android a screen
// that left with its container needs no second removal.
void main() {
  NamedRouteDef page(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => NamedPage(name),
  );

  // Opens the shop, lets the guard of its cart show the login page, then
  // leaves the shop from the root router.
  Future<RootStackRouter> leaveShopFromRedirect(WidgetTester tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('OtherRoute', '/other'),
        NamedRouteDef.shell(
          name: 'ShopRoute',
          path: '/shop',
          children: [
            page('ItemsRoute', ''),
            page('LoginRoute', 'login'),
            page(
              'CartRoute',
              'cart',
              guards: [
                AutoRouteGuard.simple(
                  (resolver, _) => unawaited(
                    resolver.redirectUntil(const NamedRoute('LoginRoute')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('ShopRoute')));
    await tester.pumpAndSettle();
    final shop = router.innerRouterOf<StackRouter>('ShopRoute')!;
    unawaited(shop.push(const NamedRoute('CartRoute')));
    await tester.pumpAndSettle();
    expect(shop.stack.map((page) => page.routeData.name), [
      'ItemsRoute',
      'LoginRoute',
    ]);

    unawaited(router.replaceAll([const NamedRoute('OtherRoute')]));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Leaving a nested router with a guard redirect open in it '
      'throws nothing and leaves the url unmarked', (tester) async {
    final router = await leaveShopFromRedirect(tester);

    expect(tester.takeException(), isNull);
    expect(router.stack.map((page) => page.routeData.name), ['OtherRoute']);
    expect(find.text('OtherRoute'), findsOneWidget);
    expect(router.navigationHistory.isUrlStateMarkedForReplace, isFalse);
  });

  // Steps: the same, then push HomeRoute and call router.back().
  // Should: the pushed page gets a history entry of its own, so one step
  // back shows OtherRoute again.
  testWidgets(
    'The page opened after leaving the nested router keeps the history entry '
    'before it',
    (tester) async {
      final router = await leaveShopFromRedirect(tester);

      unawaited(router.push(const NamedRoute('HomeRoute')));
      await tester.pumpAndSettle();
      router.back();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.routeData.name), ['OtherRoute']);
      expect(find.text('OtherRoute'), findsOneWidget);
    },
    // On the web back() moves the browser's own history, which the headless
    // runner in Chrome never writes.
    skip: kIsWeb,
  );
}
