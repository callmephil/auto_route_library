import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Neither the default AutoTabsRouter nor AutoTabsScaffold reports an init
// for the open tab when the tabs list changes and the tab's page is kept.
// Steps: AutoTabsRouter with tabs [TabA, TabB, TabC] and an
// AutoRouterObserver; on TabA, rebuild the tabs with [TabA, TabB], as an app
// does that drops a tab when the user signs in.
// Was: the observer heard didInitTabRoute(TabA) a second time, though TabA's
// State was created once; with lazyLoad: false every tab was reported again.
// The tabs set themselves up again on a routes change, reporting as at
// their start.
// Native behavior this holds to: the doc of
// AutoRouterObserver.didInitTabRoute, "called when a tab route activates",
// and in Flutter a State that is kept gets initState once.
// AutoTabsRouter.pageView is a control: it reports nothing here.
void main() {
  setUp(() {
    _events.clear();
    _initCounts.clear();
  });

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a change of the tabs list reports no init for a kept tab',
      (tester) => _expectNoInitForKeptTab(tester, kind),
    );
  }
}

Future<void> _expectNoInitForKeptTab(WidgetTester tester, _Tabs kind) async {
  final routes = ValueNotifier<List<PageRouteInfo>>(const [
    NamedRoute('TabA'),
    NamedRoute('TabB'),
    NamedRoute('TabC'),
  ]);
  addTearDown(routes.dispose);
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: ValueListenableBuilder(
            valueListenable: routes,
            builder: (_, value, _) => switch (kind) {
              .indexedStack => AutoTabsRouter(routes: value),
              .pageView => AutoTabsRouter.pageView(routes: value),
            },
          ),
        ),
        children: [
          for (final name in ['TabA', 'TabB', 'TabC'])
            NamedRouteDef(
              name: name,
              path: name.substring(3).toLowerCase(),
              builder: (_, _) => _CountedPage(name),
            ),
        ],
      ),
    ],
  );
  await pumpRouterApp(tester, router, observers: () => [_Observer()]);
  expect(_events, ['init TabA from null']);
  _events.clear();

  routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
  await tester.pumpAndSettle();

  expect(find.text('TabA'), findsOneWidget);
  expect(_initCounts['TabA'], 1);
  expect(_events, isEmpty);
}

enum _Tabs { indexedStack, pageView }

// Each tab event the observer gets, as '<init or change> <tab> from <tab>'.
final _events = <String>[];

// How often each tab's page state was created.
final _initCounts = <String, int>{};

class _Observer extends AutoRouterObserver {
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _events.add('init ${route.name} from ${previousRoute?.name ?? 'null'}');

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _events.add('change ${route.name} from ${previousRoute.name}');
}

class _CountedPage extends StatefulWidget {
  const new(this.name);

  final String name;

  @override
  State<_CountedPage> createState() => _CountedPageState();
}

class _CountedPageState extends State<_CountedPage> {
  @override
  void initState() {
    super.initState();
    _initCounts[widget.name] = (_initCounts[widget.name] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.name));
}
