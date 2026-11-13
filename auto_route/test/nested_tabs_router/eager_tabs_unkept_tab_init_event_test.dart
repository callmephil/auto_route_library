import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// With lazyLoad: false, observers hear one didInitTabRoute per page a tab
// builds, also for a tab that keeps no state.
// Steps: AutoTabsRouter that loads every tab at once, the tabs TabA and
// LiveTab, and an AutoRouterObserver. LiveTab's route doesn't maintain its
// state. Start on TabA, then open LiveTab.
// Was: the default tabs reported the init of LiveTab at the start, though
// they build such a tab only once it shows, and again when it
// opened: two inits for one page. The tabs reported every tab at their
// start without asking whether it would be built.
// Native behavior this holds to: the doc of
// AutoRouterObserver.didInitTabRoute, "called when a tab route activates",
// and in Flutter a page's State gets initState once per page built.
// AutoTabsRouter.pageView and .tabBar are controls: they build LiveTab at
// the start, so their init there is right.
void main() {
  setUp(() {
    _inits.clear();
    _initStates.clear();
  });

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: each init of a tab that keeps no state is a page built',
      (tester) => _expectOneInitPerPage(tester, kind),
    );
  }
}

Future<void> _expectOneInitPerPage(WidgetTester tester, _Tabs kind) async {
  const routes = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('LiveTab')];
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .indexedStack => const AutoTabsRouter(
              routes: routes,
              lazyLoad: false,
            ),
            .pageView => const AutoTabsRouter.pageView(
              routes: routes,
              lazyLoad: false,
            ),
            .tabBar => const AutoTabsRouter.tabBar(
              routes: routes,
              lazyLoad: false,
            ),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'TabA',
            path: 'a',
            builder: (_, _) => const _CountedPage('TabA'),
          ),
          NamedRouteDef(
            name: 'LiveTab',
            path: 'live',
            maintainState: false,
            builder: (_, _) => const _CountedPage('LiveTab'),
          ),
        ],
      ),
    ],
  );
  await pumpRouterApp(tester, router, observers: () => [_Observer()]);
  final atStart = (_inits['LiveTab'] ?? 0, _initStates['LiveTab'] ?? 0);

  router.innerRouterOf<TabsRouter>('HomeRoute')!.setActiveIndex(1);
  await tester.pumpAndSettle();

  expect(find.text('LiveTab'), findsOneWidget);
  expect(
    (atStart.$1 == atStart.$2, _inits['LiveTab'], _initStates['LiveTab']),
    (true, 1, 1),
  );
}

enum _Tabs { indexedStack, pageView, tabBar }

// How often each tab was reported through didInitTabRoute.
final _inits = <String, int>{};

// How often each tab's page state was created.
final _initStates = <String, int>{};

class _Observer extends AutoRouterObserver {
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _inits[route.name] = (_inits[route.name] ?? 0) + 1;
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
    _initStates[widget.name] = (_initStates[widget.name] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.name));
}
