@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import 'browser_history.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// On the web, a url of a tab the app had removed from its tabs list, typed
// into the address bar or reached with the browser's forward button, was
// taken as let in: the address bar and urlState named the removed tab while
// another tab showed, and back then changed nothing on screen. The owner
// decided that such a link is turned down on every platform.
// Setup: tabs A, B and C, each with a stack of two pages. A2 pushed in tab
// A, then tab C opened, then the tabs list rebuilt as [A, B]: the browser
// steps back to A2's entry, with C's entry ahead.
// Steps: type /c or /c/2, or press the browser's forward button onto C's
// old entry; then press back and forward.
// Was: the address bar at /c, with A2 on screen, for /c and the forward
// button; /c/2 was already turned down.
// Should: the browser back at A2's entry, A2 on screen at /a/2, and back and
// forward walk the entries of A1 and A2.
// Native behavior this holds to: a browser can't cancel a traversal the app
// receives, so the app steps it back to the entry of the page it shows, as a
// traversal canceled through the Navigation API (NavigateEvent
// .preventDefault) leaves the browser where it stood, the address bar
// naming what is on screen; UITabBarController can select only a view
// controller in its viewControllers array.
const List<PageRouteInfo> _kTabs = [
  NamedRoute('TabA'),
  NamedRoute('TabB'),
  NamedRoute('TabC'),
];

Future<RootStackRouter> _pumpOnTabC(
  WidgetTester tester,
  ValueNotifier<List<PageRouteInfo>> routes,
) async {
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: ValueListenableBuilder(
            valueListenable: routes,
            builder: (_, value, _) => AutoTabsRouter(routes: value),
          ),
        ),
        children: [
          for (final tab in ['A', 'B', 'C'])
            AutoRoute(
              path: tab.toLowerCase(),
              page: EmptyShellRoute('Tab$tab'),
              children: [
                for (final (path, name) in [('', '${tab}1'), ('2', '${tab}2')])
                  NamedRouteDef(
                    name: name,
                    path: path,
                    builder: (_, _) => Center(child: Text(name)),
                  ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
  await settleBrowser(tester);
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  unawaited(tabs.stackRouterOfIndex(0)!.push(const NamedRoute('A2')));
  await settleBrowser(tester);
  tabs.setActiveIndex(2);
  await settleBrowser(tester);
  return router;
}

// The browser's entry, counted from the app's first, and its path; the page
// on screen, the active tab and the url the router holds.
String _describe(RootStackRouter router, int first) {
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  final shown = [
    for (final name in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
      if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
  ];
  return 'entry ${browserSerialCount - first} $browserPath, shown '
      '${shown.join(' ')}, tab ${tabs.activeIndex} of ${tabs.pageCount}, '
      'urlState ${router.urlState.url}';
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  for (final how in ['typed /c', 'typed /c/2', 'forward button']) {
    testWidgets('On web, a url of a removed tab, $how, is turned down', (
      tester,
    ) async {
      final routes = ValueNotifier<List<PageRouteInfo>>(_kTabs);
      addTearDown(routes.dispose);
      final first = browserSerialCount < 0 ? 0 : browserSerialCount;
      final router = await _pumpOnTabC(tester, routes);
      expect(
        _describe(router, first),
        'entry 2 /c, shown C1, tab 2 of 3, urlState /c',
      );
      routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
      await settleBrowser(tester);
      // What the browser and the app show after the removal, after the url
      // of tab C, after back and after forward.
      final seen = [_describe(router, first)];

      if (how == 'forward button') {
        await pressBrowserForward(tester);
      } else {
        final path = how.substring('typed '.length);
        await browserMove(tester, () => window.location.hash = path);
      }
      await settleBrowser(tester);
      seen.add(_describe(router, first));
      await pressBrowserBack(tester);
      seen.add(_describe(router, first));
      await pressBrowserForward(tester);
      seen.add(_describe(router, first));

      expect(tester.takeException(), isNull);
      const onA2 = 'entry 1 /a/2, shown A2, tab 0 of 2, urlState /a/2';
      expect(seen, [
        onA2,
        onA2,
        'entry 0 /a, shown A1, tab 0 of 2, urlState /a',
        onA2,
      ]);
    });
  }
}
