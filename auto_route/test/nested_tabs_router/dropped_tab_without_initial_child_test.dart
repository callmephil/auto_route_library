import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab that keeps no state and whose nested router has no initial child
// shows its listed pages when it is opened again.
// Setup: the tabs FeedTab and ProfileTab, ProfileTab listed with the children
// ProfileInfoRoute and ProfileOrdersRoute. ProfileTab has maintainState
// false, and its nested router has no page at the path ''.
// Steps: open ProfileTab, by its listed pages or by the path
// '/profiletab/orders'. Open FeedTab, which drops ProfileTab's nested router.
// Open ProfileTab again, with setActiveIndex or with the tabs router's
// navigate.
// Was: setActiveIndex opened it with no page at all, under the url
// '/profiletab'. The nested router, built again, had no pages waiting and no
// initial child to open. navigate opened the pages of the tab's first route,
// so a tab first opened by a path came back on that path's page alone.
// Should: ProfileInfoRoute with ProfileOrdersRoute on top, by either call, as
// the tabs list gives them. A tab with an initial child still opens on that
// child alone (the control), as decided for a tab that keeps no state.
// The builder kind builds every tab at the start and drops none, so it
// already showed the listed pages.
// Native behavior this holds to: Flutter's Navigator never shows an empty
// pages list (it asserts there is at least one page). A tab of an Android
// bottom navigation always has a start destination, and a UIKit tab's
// UINavigationController always has a root view controller, so a tab opened
// again shows the screens it was set up with.
void main() {
  for (final kind in _Tabs.values) {
    for (final byPath in [false, true]) {
      for (final byNavigate in [false, true]) {
        testWidgets('${kind.name}: opened '
            '${byPath ? 'by a path' : 'with its listed pages'}, dropped and '
            'opened again by ${byNavigate ? 'navigate' : 'setActiveIndex'}, '
            'it shows its listed pages', (tester) async {
          final router = _buildRouter(kind);
          await pumpRouterApp(tester, router);
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
          if (byPath) {
            unawaited(router.navigatePath('/profiletab/orders'));
          } else {
            tabs.setActiveIndex(1);
          }
          await tester.pumpAndSettle();
          expect(find.text('ProfileOrdersRoute'), findsOneWidget);
          tabs.setActiveIndex(0);
          await tester.pumpAndSettle();

          if (byNavigate) {
            unawaited(tabs.navigate(const NamedRoute('ProfileTab')));
          } else {
            tabs.setActiveIndex(1);
          }
          await tester.pumpAndSettle();

          expect(_profilePages(tabs), [
            'ProfileInfoRoute',
            'ProfileOrdersRoute',
          ]);
          expect(find.text('ProfileOrdersRoute').hitTestable(), findsOneWidget);
          expect(router.urlState.url, '/profiletab/orders');
        });
      }
    }
  }

  // The same tab listed with no pages, so a path is what first opens it on a
  // page. Found by the review of this fix, whose first form opened such a
  // tab again with no page: the tabs list gave it none to wait for, and
  // navigate no longer read the pages of its route.
  // Should: it opens again on the path's page, as navigate did before the
  // fix, by either call.
  for (final kind in _Tabs.values) {
    for (final byNavigate in [false, true]) {
      testWidgets('${kind.name}: listed with no pages, opened by a path, '
          'dropped and opened again by '
          '${byNavigate ? 'navigate' : 'setActiveIndex'}, it shows the '
          "path's page", (tester) async {
        final router = _buildRouter(kind, listsPages: false);
        await pumpRouterApp(tester, router);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
        unawaited(router.navigatePath('/profiletab/orders'));
        await tester.pumpAndSettle();
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();

        if (byNavigate) {
          unawaited(tabs.navigate(const NamedRoute('ProfileTab')));
        } else {
          tabs.setActiveIndex(1);
        }
        await tester.pumpAndSettle();

        expect(_profilePages(tabs), ['ProfileOrdersRoute']);
        expect(router.urlState.url, '/profiletab/orders');
      });
    }
  }

  testWidgets('with a guard that answers later, the tab opened again shows '
      'its listed pages once the guard lets it in', (tester) async {
    final router = _buildRouter(.indexedStack, hasSlowGuard: true);
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();

    tabs.setActiveIndex(1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(_profilePages(tabs), ['ProfileInfoRoute', 'ProfileOrdersRoute']);
    expect(tabs.activeIndex, 1);
  });

  testWidgets('control: a tab with an initial child opened again shows that '
      'child', (tester) async {
    final router = _buildRouter(.indexedStack, hasInitialChild: true);
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();

    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(_profilePages(tabs), ['ProfileInfoRoute']);
    expect(router.urlState.url, '/profiletab');
  });
}

enum _Tabs { indexedStack, pageView, tabBar, builder }

List<String> _profilePages(TabsRouter tabs) => [
  ...?tabs.stackRouterOfIndex(1)?.stackData.map((data) => data.name),
];

final _slowGuard = AutoRouteGuard.simple((resolver, _) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  resolver.next();
});

RootStackRouter _buildRouter(
  _Tabs kind, {
  bool hasInitialChild = false,
  bool hasSlowGuard = false,
  bool listsPages = true,
}) {
  final routes = [
    const NamedRoute<Object?>('FeedTab'),
    if (listsPages)
      const NamedRoute<Object?>(
        'ProfileTab',
        children: [
          NamedRoute('ProfileInfoRoute'),
          NamedRoute('ProfileOrdersRoute'),
        ],
      )
    else
      const NamedRoute<Object?>('ProfileTab'),
  ];
  return .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .indexedStack => AutoTabsRouter(routes: routes),
            .pageView => AutoTabsRouter.pageView(routes: routes),
            .tabBar => AutoTabsRouter.tabBar(routes: routes),
            .builder => AutoTabsRouter.builder(
              routes: routes,
              builder: (_, children, tabs) =>
                  IndexedStack(index: tabs.activeIndex, children: children),
            ),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'FeedTab',
            path: 'feedtab',
            builder: (_, _) => const Center(child: Text('FeedTab')),
          ),
          NamedRouteDef(
            name: 'ProfileTab',
            path: 'profiletab',
            maintainState: false,
            guards: [if (hasSlowGuard) _slowGuard],
            builder: (_, _) => const AutoRouter(),
            children: [
              NamedRouteDef(
                name: 'ProfileInfoRoute',
                path: hasInitialChild ? '' : 'info',
                builder: (_, _) =>
                    const Center(child: Text('ProfileInfoRoute')),
              ),
              NamedRouteDef(
                name: 'ProfileOrdersRoute',
                path: 'orders',
                builder: (_, _) =>
                    const Center(child: Text('ProfileOrdersRoute')),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
