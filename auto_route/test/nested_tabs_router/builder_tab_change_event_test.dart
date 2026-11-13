import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The builder kind of AutoTabsRouter tells observers, AutoRouteAware pages
// and onNavigate of a tab change only when another tab shows.
// Steps: tabs [TabA, TabB, TabC] and an AutoRouterObserver; TabC's guard
// rejects. First test: on TabA, choose TabC. Second test: open TabB, then
// navigate to TabB again with a query parameter, as a link into the open
// tab does. Third test: open TabB, rebuild the tabs with [TabB, TabA], so
// TabB moves to index 0, then give TabB a query parameter.
// Was: didChangeTabRoute(TabA from TabA) after the rejection, and a second
// didChangeTabRoute(TabB from TabA) for the new params, with onNavigate
// each time. The builder reported on every notification of the tabs router
// while activeIndex differed from previousIndex, which holds from the first
// change on, and before it too. A builder that remembered the index it
// reported still took the moved TabB for another tab. The third test runs
// the builder only: what the default tabs report on a change of the list
// is their own fix.
// Native behavior this holds to: the doc of
// AutoRouterObserver.didChangeTabRoute, "called when tab route
// reactivates", and UIKit calls tabBarController(_:didSelect:) once per
// selection, and Flutter's TabController notifies only when its index
// changes. The default tabs are a control: they report nothing here either.
void main() {
  setUp(() {
    _events.clear();
    _navigateCalls = 0;
  });

  for (final kind in _Tabs.values) {
    testWidgets('${kind.name}: a rejected tab change reports no tab change', (
      tester,
    ) async {
      final router = _buildRouter(kind, _allTabs());
      await pumpRouterApp(tester, router, observers: () => [_Observer()]);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
      expect(_events, ['init TabA from null']);
      _events.clear();

      tabs.setActiveIndex(2);
      await tester.pumpAndSettle();

      expect(tabs.activeIndex, 0);
      expect(_events, isEmpty);
      expect(_navigateCalls, 0);
    });

    testWidgets(
      '${kind.name}: new params for the open tab report no tab change',
      (tester) async {
        final router = _buildRouter(kind, _allTabs());
        await pumpRouterApp(tester, router, observers: () => [_Observer()]);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        expect(_events, hasLength(2));
        _events.clear();
        _navigateCalls = 0;

        unawaited(
          router.navigate(
            const NamedRoute(
              'HomeRoute',
              children: [
                NamedRoute('TabB', queryParams: {'sort': 'new'}),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tabs.activeIndex, 1);
        expect(router.urlState.url, '/b?sort=new');
        expect(_events, isEmpty);
        expect(_navigateCalls, 0);
      },
    );
  }

  testWidgets(
    'builder: the open tab moved to another index reports no tab change',
    (tester) async {
      final names = _allTabs();
      final router = _buildRouter(.builder, names);
      await pumpRouterApp(tester, router, observers: () => [_Observer()]);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
        ..setActiveIndex(1);
      await tester.pumpAndSettle();
      _events.clear();

      names.value = ['TabB', 'TabA'];
      await tester.pumpAndSettle();
      expect((tabs.activeIndex, tabs.current.name), (0, 'TabB'));
      _navigateCalls = 0;
      unawaited(
        router.navigate(
          const NamedRoute(
            'HomeRoute',
            children: [
              NamedRoute('TabB', queryParams: {'sort': 'new'}),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TabB').hitTestable(), findsOneWidget);
      expect(_events, isEmpty);
      expect(_navigateCalls, 0);
    },
  );
}

enum _Tabs { builder, indexedStack }

// Each tab event the observer gets, as '<init or change> <tab> from <tab>'.
final _events = <String>[];

// How often the builder's onNavigate was called.
var _navigateCalls = 0;

class _Observer extends AutoRouterObserver {
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _events.add('init ${route.name} from ${previousRoute?.name ?? 'null'}');

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _events.add('change ${route.name} from ${previousRoute.name}');
}

// The three tabs, disposed with the test.
ValueNotifier<List<String>> _allTabs() {
  final names = ValueNotifier(['TabA', 'TabB', 'TabC']);
  addTearDown(names.dispose);
  return names;
}

// [names] are the tabs shown, in order.
RootStackRouter _buildRouter(_Tabs kind, ValueListenable<List<String>> names) {
  return .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: ValueListenableBuilder(
            valueListenable: names,
            builder: (_, shown, _) {
              final routes = [
                for (final name in shown) NamedRoute<Object?>(name),
              ];
              return switch (kind) {
                .builder => AutoTabsRouter.builder(
                  routes: routes,
                  onNavigate: (_) => _navigateCalls++,
                  builder: (_, children, tabsRouter) => IndexedStack(
                    index: tabsRouter.activeIndex,
                    children: children,
                  ),
                ),
                .indexedStack => AutoTabsRouter(routes: routes),
              };
            },
          ),
        ),
        children: [
          for (final name in ['TabA', 'TabB', 'TabC'])
            NamedRouteDef(
              name: name,
              path: name.substring(3).toLowerCase(),
              guards: [
                if (name == 'TabC')
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
              ],
              builder: (_, _) => Center(child: Text(name)),
            ),
        ],
      ),
    ],
  );
}
