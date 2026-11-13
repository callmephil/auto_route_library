import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Two tab changes before the next frame: each event names the tab the change
// left as its previous tab.
// Steps: the tabs FeedTab, ProfileTab and SettingsTab, each opened once, and
// an AutoRouterObserver. On SettingsTab, call setActiveIndex twice in one
// turn, or navigatePath to ProfileTab and setActiveIndex to FeedTab in one
// turn, which the tabs take as FeedTab, then ProfileTab.
// Was: the default tabs named SettingsTab as the previous tab of both
// changes. They read the active index of their last build, and no frame was
// built on FeedTab. The page-view, tab-bar and builder tabs are controls:
// they read the router's tabs.
// Native behavior this holds to: Flutter's TabController sets previousIndex
// to the index it leaves on every change, also for two in one frame.
void main() {
  setUp(_events.clear);

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: two setActiveIndex calls in one turn name the tab each '
      'left',
      (tester) async {
        final tabs = await _start(tester, kind);

        tabs
          ..setActiveIndex(0)
          ..setActiveIndex(1);
        await tester.pumpAndSettle();

        expect(_events, [
          'change FeedTab from SettingsTab',
          'change ProfileTab from FeedTab',
        ]);
      },
    );

    testWidgets(
      '${kind.name}: a path to a tab and setActiveIndex in one turn name the '
      'tab each left',
      (tester) async {
        final tabs = await _start(tester, kind);

        unawaited(_router.navigatePath('/profiletab'));
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();

        expect(
          (tabs.current.name, _events.join('; ')),
          (
            'ProfileTab',
            'change FeedTab from SettingsTab; change ProfileTab from FeedTab',
          ),
        );
      },
    );
  }
}

enum _Tabs { indexedStack, pageView, tabBar, builder }

const _kTabNames = ['FeedTab', 'ProfileTab', 'SettingsTab'];

// Each tab change the observer hears, as 'change <tab> from <tab>'.
final _events = <String>[];

late RootStackRouter _router;

// Shows the tabs of [kind], opens each once, and ends on SettingsTab with no
// events heard.
Future<TabsRouter> _start(WidgetTester tester, _Tabs kind) async {
  final routes = [for (final name in _kTabNames) NamedRoute<Object?>(name)];
  _router = .build(
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
          for (final name in _kTabNames)
            NamedRouteDef(
              name: name,
              path: name.toLowerCase(),
              builder: (_, _) => Center(child: Text(name)),
            ),
        ],
      ),
    ],
  );
  await pumpRouterApp(tester, _router, observers: () => [_Observer()]);
  final tabs = _router.innerRouterOf<TabsRouter>('HomeRoute')!;
  for (final index in const [1, 2]) {
    tabs.setActiveIndex(index);
    await tester.pumpAndSettle();
  }
  _events.clear();
  return tabs;
}

class _Observer extends AutoRouterObserver {
  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _events.add('change ${route.name} from ${previousRoute.name}');
}
