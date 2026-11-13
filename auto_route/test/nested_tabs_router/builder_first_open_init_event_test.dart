import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The builder kind of AutoTabsRouter reports a tab's first opening with
// didInitTabRoute, as the default tabs do, and a later return to it with
// didChangeTabRoute.
// Steps: the tabs TabA and TabB and an AutoRouterObserver. On TabA, open
// TabB, then go back to TabA, then to TabB again.
// Was: the observer heard didInitTabRoute for TabA only. TabB's first
// opening came as didChangeTabRoute(TabB from TabA), so an observer that
// counts the tabs opened, or sets one up on its init, never heard of TabB.
// The builder reported init for the tab active at its start and a change
// for every later tab.
// Native behavior this holds to: the docs of AutoRouterObserver,
// didInitTabRoute "called when a tab route activates" and
// didChangeTabRoute "called when tab route reactivates"; in UIKit a tab's
// view controller gets viewDidLoad on its first selection and
// viewWillAppear on every one. The default tabs are a control.
void main() {
  setUp(_events.clear);

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: the first opening of a tab is an init, a return a change',
      (tester) => _expectInitThenChange(tester, kind),
    );
  }
}

Future<void> _expectInitThenChange(WidgetTester tester, _Tabs kind) async {
  const routes = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('TabB')];
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .builder => AutoTabsRouter.builder(
              routes: routes,
              builder: (_, children, tabsRouter) => IndexedStack(
                index: tabsRouter.activeIndex,
                children: children,
              ),
            ),
            .indexedStack => const AutoTabsRouter(routes: routes),
          },
        ),
        children: [
          for (final name in ['TabA', 'TabB'])
            NamedRouteDef(
              name: name,
              path: name.substring(3).toLowerCase(),
              builder: (_, _) => Center(child: Text(name)),
            ),
        ],
      ),
    ],
  );
  await pumpRouterApp(tester, router, observers: () => [_Observer()]);
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

  for (final index in [1, 0, 1]) {
    tabs.setActiveIndex(index);
    await tester.pumpAndSettle();
  }

  expect(_events, [
    'init TabA from null',
    'init TabB from TabA',
    'change TabA from TabB',
    'change TabB from TabA',
  ]);
}

enum _Tabs { builder, indexedStack }

// Each tab event the observer gets, as '<init or change> <tab> from <tab>'.
final _events = <String>[];

class _Observer extends AutoRouterObserver {
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _events.add('init ${route.name} from ${previousRoute?.name ?? 'null'}');

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _events.add('change ${route.name} from ${previousRoute.name}');
}
