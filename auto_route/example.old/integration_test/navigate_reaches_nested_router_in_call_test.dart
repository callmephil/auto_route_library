import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigation through the root that names a child for the nested router or
// the tabs of an open page reaches them in the call, so a call made right
// after it in the same handler acts on them as they then are, as Flutter's
// Navigator changes its history at each call, a nested one too.
// Headless test: auto_route/test/navigate_reaches_nested_router_in_call_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigate reaches nested router in call', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: the shop at '/' shows its items page. Tap the button 'Cart then
    // checkout'. Its handler calls navigate on the root with the shop and its
    // cart page, then push with the checkout page on the shop's own router,
    // with no await between them. Go back.
    // Was: the cart page went in last, so it was on screen over the checkout
    // page.
    // Should: the checkout page is on screen, and back shows the cart.
    testWidgets('A push after navigate with a child lands above the child', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef.shell(
            name: 'ShopRoute',
            path: '/',
            children: [
              NamedRouteDef(
                name: 'ItemsRoute',
                path: '',
                builder: (context, _) => page('ItemsRoute', [
                  TextButton(
                    onPressed: () {
                      final shop = context.router;
                      unawaited(
                        shop.root.navigate(
                          const NamedRoute(
                            'ShopRoute',
                            children: [NamedRoute('CartRoute')],
                          ),
                        ),
                      );
                      unawaited(shop.push(const NamedRoute('CheckoutRoute')));
                    },
                    child: const Text('Cart then checkout'),
                  ),
                ]),
              ),
              for (final (name, path) in [
                ('CartRoute', 'cart'),
                ('CheckoutRoute', 'checkout'),
              ])
                NamedRouteDef(
                  name: name,
                  path: path,
                  builder: (_, _) => page(name),
                ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Cart then checkout'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final shop = router.innerRouterOf<StackRouter>('ShopRoute');
      expect(shop?.stack.map((page) => page.name), [
        'ItemsRoute',
        'CartRoute',
        'CheckoutRoute',
      ]);
      expect(find.text('CheckoutRoute'), findsOneWidget);
      await expectBrowserUrl('/checkout');

      await systemBack(tester);

      expect(find.text('CartRoute'), findsOneWidget);
      expect(find.text('CheckoutRoute'), findsNothing);
    });

    // Steps: tabs at '/' with a Feed and a Profile tab, on Feed. Tap the
    // button 'Profile then stay'. Its handler calls navigatePath with the
    // Profile tab's path on the root and then setActiveIndex with the Feed
    // tab's index on the tabs, with no await between them.
    // Was: the Profile tab showed, since the path reached the tabs after
    // the later call.
    // Should: the Feed tab shows, the later call.
    testWidgets('setActiveIndex after a path to a tab is the one that shows', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const AutoTabsRouter(
              routes: [NamedRoute('FeedRoute'), NamedRoute('ProfileRoute')],
            ),
            children: [
              NamedRouteDef(
                name: 'FeedRoute',
                path: 'feed',
                builder: (context, _) => page('FeedRoute', [
                  TextButton(
                    onPressed: () {
                      final tabs = context.tabsRouter;
                      unawaited(tabs.root.navigatePath('/profile'));
                      tabs.setActiveIndex(0);
                    },
                    child: const Text('Profile then stay'),
                  ),
                ]),
              ),
              NamedRouteDef(
                name: 'ProfileRoute',
                path: 'profile',
                builder: (_, _) => page('ProfileRoute'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Profile then stay'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.innerRouterOf<TabsRouter>('HomeRoute')?.activeIndex, 0);
      expect(find.text('FeedRoute'), findsOneWidget);
      expect(find.text('ProfileRoute'), findsNothing);
      await expectBrowserUrl('/feed');
    });
  });
}
