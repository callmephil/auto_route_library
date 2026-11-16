@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// When the active tab is taken out of the tabs list, the browser's address
// bar and its back button follow the page shown instead.
// Setup: tabs [A, B, C], each with its own stack, in a browser.
// Steps: push A2 in tab A, open tab C, then rebuild AutoTabsRouter with
// [A, B]. Tab A shows again, on A2. Press the browser's back button.
// Was: the url of A2 went into a new browser entry over the one of C, so the
// back button put '/c' in the address bar while A2 stayed on screen, since
// tab C was gone. Then, until the web history became the browser's one
// writer, the url of A2 was written over C's entry, which gave A2 two
// entries: the first press of the back button changed nothing on screen.
// Should: the browser steps back to the entry of A2 the user opened, as it
// does for any page that closes, and the address bar names the page on
// screen at every step. One press of the back button then shows A1, as
// system back does.
// Native behavior this holds to: Flutter's Navigator, where a route removed
// from the top shows the one under it and the system back then closes that
// one. A browser can't take an entry out, so C's stays ahead of the one the
// browser stands on, where only the forward button reaches it.
// Headless test off the web:
// test/nested_tabs_router/active_tab_removed_test.dart
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('The browser back button after the active tab is removed '
      'shows the url of the page on screen', (tester) async {
    final routes = ValueNotifier<List<PageRouteInfo>>(_kTabs);
    addTearDown(routes.dispose);
    final router = await _pumpOnTabC(tester, routes);
    final entryOfC = browserSerialCount;

    routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
    await settleBrowser(tester);

    // The entry of A2 the user opened.
    expect(find.text('A2'), findsOneWidget);
    expect((browserSerialCount, browserPath), (entryOfC - 1, '/a/2'));
    expect(router.urlState.url, '/a/2');

    await pressBrowserBack(tester);

    expect(find.text('A1'), findsOneWidget);
    expect((browserSerialCount, browserPath), (entryOfC - 2, '/a'));
  });

  testWidgets('System back after the active tab is removed pops the page on '
      'screen', (tester) async {
    final routes = ValueNotifier<List<PageRouteInfo>>(_kTabs);
    addTearDown(routes.dispose);
    final router = await _pumpOnTabC(tester, routes);
    routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
    await settleBrowser(tester);

    await tester.binding.handlePopRoute();
    await settleBrowser(tester);

    expect(find.text('A1'), findsOneWidget);
    expect(browserPath, '/a');
    expect(router.urlState.url, '/a');
  });
}

const List<PageRouteInfo> _kTabs = [
  NamedRoute('TabA'),
  NamedRoute('TabB'),
  NamedRoute('TabC'),
];

// Opens the tabs, pushes A2 in tab A and leaves the app on tab C.
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
  await pumpRouterConfigApp(tester, router.config());
  await settleBrowser(tester);
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  unawaited(tabs.stackRouterOfIndex(0)!.push(const NamedRoute('A2')));
  await settleBrowser(tester);
  tabs.setActiveIndex(2);
  await settleBrowser(tester);
  expect(find.text('C1'), findsOneWidget);
  expect(browserPath, '/c');
  return router;
}
