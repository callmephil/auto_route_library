import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The default AutoTabsRouter reports every switch to a tab whose route has
// maintainState: false, also with lazyLoad: false.
// Steps: tabs Tab1 and Tab2 (maintainState: false) and an
// AutoRouterObserver. Switch to Tab2, back to Tab1, and to Tab2 again.
// Was: with lazyLoad: false the switches to Tab2 reported nothing, neither
// didInitTabRoute nor didChangeTabRoute: the tabs reported a change only for
// a tab still loaded, and an init only when they load lazily, and a tab
// that keeps no state is dropped while another shows.
// Native behavior this holds to: the docs of AutoRouterObserver,
// didInitTabRoute "called when a tab route activates" and didChangeTabRoute
// "called when tab route reactivates"; UIKit calls
// tabBarController(_:didSelect:) on every selection. lazyLoad: true, and
// AutoTabsRouter.pageView with the same options, already reported it.
final _tabEvents = <String>[];

class _TabsObserver extends AutoRouterObserver {
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _tabEvents.add(
        'didInitTabRoute ${route.name} from ${previousRoute?.name ?? 'null'}',
      );

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _tabEvents.add(
        'didChangeTabRoute ${route.name} from ${previousRoute.name}',
      );
}

PageInfo _tabPage(String name) =>
    .new(name, builder: (_) => Center(child: Text(name)));

Future<TabsRouter> _pumpTabs(
  WidgetTester tester, {
  required bool lazyLoad,
}) async {
  final router = RootStackRouter.build(
    routes: [
      AutoRoute(
        path: '/',
        page: PageInfo(
          'TabsRoute',
          builder: (_) => AutoTabsRouter(
            lazyLoad: lazyLoad,
            routes: const [NamedRoute('Tab1'), NamedRoute('Tab2')],
          ),
        ),
        children: [
          AutoRoute(path: 'tab1', page: _tabPage('Tab1')),
          AutoRoute(path: 'tab2', page: _tabPage('Tab2'), maintainState: false),
        ],
      ),
    ],
  );
  _tabEvents.clear();
  await pumpRouterConfigApp(
    tester,
    router.config(navigatorObservers: () => [_TabsObserver()]),
  );
  return router.innerRouterOf<TabsRouter>('TabsRoute')!;
}

// Shows the tab at [index] and returns the tab events it reported, joined.
Future<String> _switchTo(
  WidgetTester tester,
  TabsRouter tabsRouter,
  int index,
) async {
  _tabEvents.clear();
  tabsRouter.setActiveIndex(index);
  await tester.pumpAndSettle();
  expect(tabsRouter.activeIndex, index);
  return _tabEvents.join('; ');
}

// A report without its event's name, as 'Tab2 from Tab1'.
String _withoutKind(String report) => report.substring(report.indexOf(' ') + 1);

void main() {
  for (final lazyLoad in [true, false]) {
    testWidgets(
      'lazyLoad: $lazyLoad, every switch to a tab that keeps no state reports '
      'the tab shown',
      (tester) async {
        final tabsRouter = await _pumpTabs(tester, lazyLoad: lazyLoad);
        _tabEvents.clear();

        // Each switch reports one event; the one back to Tab1, kept, is a
        // change.
        final reports = [
          for (final index in const [1, 0, 1])
            await _switchTo(tester, tabsRouter, index),
        ];
        expect(reports.map(_withoutKind), [
          'Tab2 from Tab1',
          'Tab1 from Tab2',
          'Tab2 from Tab1',
        ]);
        expect(reports, contains('didChangeTabRoute Tab1 from Tab2'));
        expect(find.text('Tab2'), findsOneWidget);
      },
    );
  }
}
