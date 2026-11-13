import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// navigate() to a page that is open and holds a nested router emptied that
// router when the route was given no children and has no initial child: the
// page went blank, and the url still named the child it had shown.
// Setup: ShopRoute at /shop holds a nested router with ItemsRoute ('items')
// and CartRoute ('cart'), neither of them initial.
// Steps: open Home, push ShopRoute with ItemsRoute, then call
// navigate(ShopRoute()) with no children, as a "back to the shop" button
// does.
// Native behavior this holds to: going back to a screen that is open shows
// it as it was. On iOS popToViewController shows the view controller with
// its content, on Android navigating with popUpTo to a destination on the
// back stack keeps the destination and its state, and Flutter's
// Navigator.popUntil leaves the route it reaches untouched.
//
// Only a route object says nothing about the pages inside. A path, a link
// and a history entry name the whole state: in a browser, going to a url or
// back to an entry shows that url's state, and on Android a link's intent
// builds the screen its uri names. So they still empty a nested router they
// name no page for, and the url follows.
void main() {
  NamedRouteDef page(String name, String path, {bool initial = false}) => .new(
    name: name,
    path: path,
    initial: initial,
    builder: (_, _) => NamedPage(name),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('navigate to an open shell with no children keeps the page its '
      'nested router shows', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        NamedRouteDef.shell(
          name: 'ShopRoute',
          path: '/shop',
          children: [page('ItemsRoute', 'items'), page('CartRoute', 'cart')],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute('ShopRoute', children: [NamedRoute('ItemsRoute')]),
      ),
    );
    await tester.pumpAndSettle();
    final shop = router.innerRouterOf<StackRouter>('ShopRoute')!;
    unawaited(shop.push(const NamedRoute('CartRoute')));
    await tester.pumpAndSettle();

    unawaited(router.navigate(const NamedRoute('ShopRoute')));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'ShopRoute']);
    expect(stackNames(shop), ['ItemsRoute', 'CartRoute']);
    expect(find.text('CartRoute'), findsOneWidget);
    expect(router.currentUrl, '/shop/cart');
  });

  // The same shell as a tab: navigate(ProfileRoute()) with no children, as a
  // tap on its tab does through the router, emptied the tab's nested router.
  // Should: the tab shows the page it showed, as a tab bar on iOS and a
  // bottom navigation on Android keep each tab's own stack.
  testWidgets('navigate to an open tab with no children keeps the page its '
      'nested router shows', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'AppRoute',
          path: '/',
          builder: (_, _) => const AutoTabsScaffold(
            routes: [
              NamedRoute('FeedRoute'),
              NamedRoute(
                'ProfileRoute',
                children: [NamedRoute('ProfileHomeRoute')],
              ),
            ],
          ),
          children: [
            page('FeedRoute', 'feed'),
            NamedRouteDef.shell(
              name: 'ProfileRoute',
              path: 'profile',
              children: [
                page('ProfileHomeRoute', 'home'),
                page('ProfileEditRoute', 'edit'),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    final tabs = router.innerRouterOf<TabsRouter>('AppRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    final profile = tabs.innerRouterOf<StackRouter>('ProfileRoute')!;
    unawaited(profile.push(const NamedRoute('ProfileEditRoute')));
    await tester.pumpAndSettle();

    unawaited(router.navigate(const NamedRoute('ProfileRoute')));
    await tester.pumpAndSettle();

    expect(stackNames(profile), ['ProfileHomeRoute', 'ProfileEditRoute']);
    expect(find.text('ProfileEditRoute'), findsOneWidget);
    expect(router.currentUrl, '/profile/edit');
  });

  // The same tab reached from the other tab: on the Feed tab,
  // navigate(ProfileRoute()) with no children, as a tap on the Profile tab
  // does through the router.
  // Should: the Profile tab shows, with the page it showed.
  testWidgets('navigate to a tab from another tab keeps its pages', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'AppRoute',
          path: '/',
          builder: (_, _) => const AutoTabsScaffold(
            routes: [
              NamedRoute('FeedRoute'),
              NamedRoute(
                'ProfileRoute',
                children: [NamedRoute('ProfileHomeRoute')],
              ),
            ],
          ),
          children: [
            page('FeedRoute', 'feed'),
            NamedRouteDef.shell(
              name: 'ProfileRoute',
              path: 'profile',
              children: [
                page('ProfileHomeRoute', 'home'),
                page('ProfileEditRoute', 'edit'),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    final tabs = router.innerRouterOf<TabsRouter>('AppRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    final profile = tabs.innerRouterOf<StackRouter>('ProfileRoute')!;
    unawaited(profile.push(const NamedRoute('ProfileEditRoute')));
    await tester.pumpAndSettle();
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();

    unawaited(tabs.navigate(const NamedRoute('ProfileRoute')));
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 1);
    expect(stackNames(profile), ['ProfileHomeRoute', 'ProfileEditRoute']);
    expect(find.text('ProfileEditRoute'), findsOneWidget);
    expect(router.currentUrl, '/profile/edit');
  });

  // A shell with an initial child goes back to that child, as before: a route
  // given no children comes with its initial child.
  testWidgets('navigate to an open shell with an initial child shows that '
      'child', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        NamedRouteDef.shell(
          name: 'ShopRoute',
          path: '/shop',
          children: [
            page('ItemsRoute', '', initial: true),
            page('CartRoute', 'cart'),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute('ShopRoute', children: [NamedRoute('CartRoute')]),
      ),
    );
    await tester.pumpAndSettle();
    final shop = router.innerRouterOf<StackRouter>('ShopRoute')!;

    unawaited(router.navigate(const NamedRoute('ShopRoute')));
    await tester.pumpAndSettle();

    expect(stackNames(shop).lastOrNull, 'ItemsRoute');
    expect(find.text('ItemsRoute'), findsOneWidget);
    expect(router.currentUrl, '/shop');
  });

  // A list with a detail pane: MailRoute at /mail holds a nested router that
  // starts empty and shows a placeholder; MessageRoute (':id') opens a mail in
  // it, at /mail/42.
  group(
    'A navigation that names the whole state empties the nested router',
    () {
      RootStackRouter buildRouter() => .build(
        routes: [
          page('HomeRoute', '/'),
          NamedRouteDef(
            name: 'MailRoute',
            path: '/mail',
            builder: (_, _) => Row(
              children: [
                const Expanded(child: Text('Inbox')),
                Expanded(
                  child: AutoRouter(
                    placeholder: (_) => const Text('Choose a mail'),
                  ),
                ),
              ],
            ),
            children: [
              NamedRouteDef(
                name: 'MessageRoute',
                path: ':id',
                builder: (_, data) =>
                    Text('Mail ${data.params.getString('id')}'),
              ),
            ],
          ),
        ],
      );

      // Opens Home, the list, then mail 42 in the pane.
      Future<RootStackRouter> openMail(WidgetTester tester) async {
        final router = buildRouter();
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('MailRoute')));
        await tester.pumpAndSettle();
        unawaited(
          router
              .innerRouterOf<StackRouter>('MailRoute')!
              .push(const NamedRoute('MessageRoute', params: {'id': '42'})),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mail 42'), findsOneWidget);
        expect(router.currentUrl, '/mail/42');
        return router;
      }

      void expectEmptyPane(RootStackRouter router) {
        expect(router.innerRouterOf<StackRouter>('MailRoute')?.stack, isEmpty);
        expect(find.text('Choose a mail'), findsOneWidget);
        expect(find.text('Mail 42'), findsNothing);
        expect(router.currentUrl, '/mail');
      }

      // Steps: on mail 42, call navigatePath('/mail').
      // Was, with the pages kept for every navigation: mail 42 stayed in the
      // pane. Before that the pane emptied but the url stayed /mail/42.
      // Should: the pane shows its placeholder, at /mail.
      testWidgets('navigatePath to the list empties the pane', (tester) async {
        final router = await openMail(tester);

        unawaited(router.navigatePath('/mail'));
        await tester.pumpAndSettle();

        expectEmptyPane(router);
      });

      // Steps: on mail 42, the platform hands the app the link /mail.
      // Should: the pane shows its placeholder, at /mail.
      testWidgets('a link to the list empties the pane', (tester) async {
        final router = await openMail(tester);

        await tester.binding.handlePushRoute('/mail');
        await tester.pumpAndSettle();

        expectEmptyPane(router);
      });

      // Steps: on mail 42, call back(), then back() again.
      // Should: the first shows the list with the placeholder, at /mail, the
      // second shows Home.
      // On the web back() is the browser's: see
      // test/web/emptied_nested_router_browser_back_web_test.dart.
      testWidgets('back() to the list empties the pane', (tester) async {
        final router = await openMail(tester);

        router.back();
        await tester.pumpAndSettle();

        expectEmptyPane(router);

        router.back();
        await tester.pumpAndSettle();

        expect(stackNames(router), ['HomeRoute']);
        expect(router.currentUrl, '/');
      }, skip: kIsWeb);

      // Steps: on mail 42, call navigate(MailRoute()) with no children.
      // Should: mail 42 stays in the pane, at /mail/42.
      testWidgets('navigate to the list with a route object keeps the mail', (
        tester,
      ) async {
        final router = await openMail(tester);

        unawaited(router.navigate(const NamedRoute('MailRoute')));
        await tester.pumpAndSettle();

        expect(find.text('Mail 42'), findsOneWidget);
        expect(router.currentUrl, '/mail/42');
      });
    },
  );
}
