import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// AutoTabsRouter.pageView opened under another page shows the tab it is
// given, without an error.
// Steps: the app opens on [Home, Details], as a link, a restored session or
// replaceAll([Home, Details]) opens it, so Home's page view is built but
// never laid out. Then navigate to a tab of Home from Details, or call
// setActiveIndex and pop Details.
// Was: "Null check operator used on a null value" from the page view, which
// read its controller's page before the first layout, and the tabs stayed on
// the old tab while the router said another was active.
// Native behavior this holds to: selecting a tab of a UITabBarController or
// a NavigationBarView whose screen is covered selects it, and it shows once
// uncovered. Flutter's PageController.jumpToPage keeps a page asked for
// before the first layout as the page to start on, and Flutter's TabBarView
// reads its page controller's page without assuming it is there. The last
// test is a control: AutoTabsRouter.tabBar takes the same steps.
void main() {
  testWidgets(
    'pageView: navigating to a tab of tabs opened under another page shows it',
    (tester) async {
      final router = await _pumpDetailsOverTabs(
        tester,
        const AutoTabsRouter.pageView(routes: _kTabs),
      );
      expect(find.text('Details'), findsOneWidget);

      unawaited(
        router.navigate(
          const NamedRoute('HomeRoute', children: [NamedRoute('TabC')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 2);
      expect(find.text('TabC'), findsOneWidget);
    },
  );

  testWidgets(
    'pageView: a tab chosen while the tabs are covered shows after the pop',
    (tester) async {
      final router = await _pumpDetailsOverTabs(
        tester,
        const AutoTabsRouter.pageView(routes: _kTabs),
      );
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
        ..setActiveIndex(1);
      await tester.pumpAndSettle();
      final errorWhileCovered = tester.takeException();

      router.pop();
      await tester.pumpAndSettle();

      expect((errorWhileCovered, tester.takeException()), (null, null));
      expect(tabs.activeIndex, 1);
      expect(find.text('TabB'), findsOneWidget);
    },
  );

  testWidgets('control, passes today: the same steps with tabBar', (
    tester,
  ) async {
    final router = await _pumpDetailsOverTabs(
      tester,
      const AutoTabsRouter.tabBar(routes: _kTabs),
    );
    unawaited(
      router.navigate(
        const NamedRoute('HomeRoute', children: [NamedRoute('TabC')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 2);
    expect(find.text('TabC'), findsOneWidget);
  });
}

const List<PageRouteInfo> _kTabs = [
  NamedRoute('TabA'),
  NamedRoute('TabB'),
  NamedRoute('TabC'),
];

// Opens the app on [HomeRoute, DetailsRoute]: the tabs are under the details
// page from the first frame.
Future<RootStackRouter> _pumpDetailsOverTabs(
  WidgetTester tester,
  Widget tabs,
) async {
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(body: tabs),
        children: [
          for (final name in ['TabA', 'TabB', 'TabC'])
            NamedRouteDef(
              name: name,
              path: name.substring(3).toLowerCase(),
              builder: (_, _) => Center(child: Text(name)),
            ),
        ],
      ),
      NamedRouteDef(
        name: 'DetailsRoute',
        path: '/details',
        builder: (_, _) => const Scaffold(body: Center(child: Text('Details'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routeInformationParser: router.defaultRouteParser(),
      routerDelegate: router.delegate(
        deepLinkBuilder: (_) => const DeepLink([
          NamedRoute('HomeRoute'),
          NamedRoute('DetailsRoute'),
        ]),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
