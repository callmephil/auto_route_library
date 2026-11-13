import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
import '../router_test_utils.dart';

// When the active tab is taken out of the tabs list, another tab shows, and
// the url and Android's back hear of it.
// Setup: tabs [A, B, C], each with its own stack; the app is on Android.
// Steps: push a second page in tab A, open tab C, then rebuild
// AutoTabsRouter with [A, B], as an app does that swaps a sign-in tab for an
// account tab or drops a tab. Tab A shows again, on its second page.
// Was: the url stayed C's, '/c', and Flutter still told Android the app did
// not take back, so on Android 13 and later back closed the app instead of
// popping A's second page. TabsRouter.replaceAll set the active index
// without telling anyone, so neither the url nor the navigator inside tab A,
// which listens to the tabs router to learn whether its tab is on screen,
// heard of it. Tabs that appear in a list that was empty left the url at '/'
// the same way.
// Should: the url is that of the page now on screen, '/a/2', and the app
// tells Android it takes back.
// Native behavior this holds to: on the web the url names what is on screen,
// as it does after setActiveIndex (test/shell/url_after_tab_switch_test.dart).
// On Android, back pops the page on top of the tab on screen; Flutter reports
// whether it takes back through SystemNavigator.setFrameworkHandlesBack, and
// while that is false Android closes the app itself. The control shows the
// same tab reached with setActiveIndex.
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: the url follows the tab shown after the active tab is '
      'removed',
      (tester) async {
        final routes = ValueNotifier<List<PageRouteInfo>>(_kTabs);
        addTearDown(routes.dispose);
        final (router, tabs, _) = await _pumpTabs(tester, kind, routes);
        expect(router.urlState.url, '/c');

        routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
        await tester.pumpAndSettle();

        expect(tabs.current.name, 'TabA');
        expect(find.text('A2'), findsOneWidget);
        expect(router.urlState.url, '/a/2');
      },
    );

    testWidgets(
      '${kind.name}: Android back stays in the app after the active tab is '
      'removed',
      (tester) async {
        final routes = ValueNotifier<List<PageRouteInfo>>(_kTabs);
        addTearDown(routes.dispose);
        final (_, tabs, recorder) = await _pumpTabs(tester, kind, routes);
        // On C's first page nothing can pop.
        expect(recorder.isHandlingBack, isFalse);

        routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
        await tester.pumpAndSettle();

        expect(tabs.current.name, 'TabA');
        expect(find.text('A2'), findsOneWidget);
        expect(
          recorder.isHandlingBack,
          isTrue,
          reason: 'Android would close the app on back',
        );
      },
    );

    testWidgets('${kind.name}, control: the same tab reached with '
        'setActiveIndex', (tester) async {
      final routes = ValueNotifier<List<PageRouteInfo>>(_kTabs);
      addTearDown(routes.dispose);
      final (router, tabs, recorder) = await _pumpTabs(tester, kind, routes);

      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();

      expect(find.text('A2'), findsOneWidget);
      expect(router.urlState.url, '/a/2');
      expect(recorder.isHandlingBack, isTrue);
    });
  }

  testWidgets('the url follows tabs that appear in an empty list', (
    tester,
  ) async {
    final routes = ValueNotifier<List<PageRouteInfo>>(const []);
    addTearDown(routes.dispose);
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
    await pumpRouterApp(tester, router);
    expect(router.urlState.url, '/');

    routes.value = const [NamedRoute('TabA'), NamedRoute('TabB')];
    await tester.pumpAndSettle();

    expect(find.text('TabA'), findsOneWidget);
    expect(router.urlState.url, '/a');
  });
}

enum _Tabs { indexedStack, pageView, tabBar }

const List<PageRouteInfo> _kTabs = [
  NamedRoute('TabA'),
  NamedRoute('TabB'),
  NamedRoute('TabC'),
];

// Opens the tabs, pushes A2 in tab A and leaves the app on tab C.
Future<(RootStackRouter, TabsRouter, FrameworkHandlesBackRecorder)> _pumpTabs(
  WidgetTester tester,
  _Tabs kind,
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
            builder: (_, value, _) => switch (kind) {
              .indexedStack => AutoTabsRouter(routes: value),
              .pageView => AutoTabsRouter.pageView(routes: value),
              .tabBar => AutoTabsRouter.tabBar(routes: value),
            },
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
  final recorder = FrameworkHandlesBackRecorder()..listen(tester);
  await tester.pumpWidget(
    MaterialApp.router(theme: androidTheme, routerConfig: router.config()),
  );
  await tester.pumpAndSettle();
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  unawaited(tabs.stackRouterOfIndex(0)!.push(const NamedRoute('A2')));
  await tester.pumpAndSettle();
  expect(find.text('A2'), findsOneWidget);
  expect(recorder.isHandlingBack, isTrue);
  tabs.setActiveIndex(2);
  await tester.pumpAndSettle();
  expect(find.text('C1'), findsOneWidget);
  return (router, tabs, recorder);
}
