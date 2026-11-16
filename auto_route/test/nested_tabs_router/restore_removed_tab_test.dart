@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../restoration/restoration_test_utils.dart';
import '../router_test_utils.dart';

// Found by the batch's final check; no upstream issue.
// An app restored after the platform ended it, whose saved tabs page was on
// a tab the app has since removed from its tabs list, lost the tabs page
// and threw "Can not navigate to ProfileTab: it is not one of the tabs".
// On dev 921fce58 the tabs page came back on its first tab.
// The cause: the tabs router turned the restore down as it turns down a
// link or the app's own navigation to a removed tab, took its page back
// and, with no onFailure to tell, threw.
// Setup: Landing at '/', Home at '/home' with the tabs Feed, Profile and
// Settings. Home opened on Profile, the app saved, Profile removed from
// the tabs list, the app restored. Each kind of tabs widget, and the
// neighbors below.
// Should: Home back on its first tab, at '/home/feed', with the pages
// around it, and nothing thrown. A restore is neither a link nor the app's
// own call: nobody can be told, and no page is on screen to keep. An app
// launched at the removed tab's url is still turned down.
// Native behavior this holds to: the package's own rule, as before the
// batch: a restore brings back what it can.
enum _Tabs { indexedStack, pageView, tabBar, builder }

const _feed = NamedRoute<Object?>('FeedTab');
const _profile = NamedRoute<Object?>('ProfileTab');
const _settings = NamedRoute<Object?>('SettingsTab');
const _tabNames = ['FeedTab', 'ProfileTab', 'SettingsTab'];

Widget _tabsOf(_Tabs kind, List<PageRouteInfo> routes) => switch (kind) {
  .indexedStack => AutoTabsRouter(routes: routes),
  .pageView => AutoTabsRouter.pageView(routes: routes),
  .tabBar => AutoTabsRouter.tabBar(routes: routes),
  .builder => AutoTabsRouter.builder(
    routes: routes,
    builder: (_, children, tabs) =>
        IndexedStack(index: tabs.activeIndex, children: children),
  ),
};

NamedRouteDef _page(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => Scaffold(body: Center(child: Text(name))),
);

// The tabs page [name] at [path], showing the tabs in [list].
NamedRouteDef _tabsPage(
  String name,
  String path,
  _Tabs kind,
  ValueNotifier<List<PageRouteInfo>> list,
) => .new(
  name: name,
  path: path,
  builder: (_, _) => Scaffold(
    body: ValueListenableBuilder(
      valueListenable: list,
      builder: (_, routes, _) => _tabsOf(kind, routes),
    ),
  ),
  children: [
    for (final tab in _tabNames)
      _page(tab, tab.replaceAll('Tab', '').toLowerCase()),
  ],
);

// Landing at '/', Home at '/home', Detail at '/detail', and a shell at
// '/shell' that holds Home's tabs again, as InnerHome at '/shell/home'.
RootStackRouter _build(_Tabs kind, ValueNotifier<List<PageRouteInfo>> list) =>
    .build(
      routes: [
        _page('LandingRoute', '/'),
        _tabsPage('HomeRoute', '/home', kind, list),
        _page('DetailRoute', '/detail'),
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/shell',
          builder: (_, _) => const Scaffold(body: AutoRouter()),
          children: [
            _page('ShellStartRoute', ''),
            _tabsPage('InnerHomeRoute', 'home', kind, list),
          ],
        ),
      ],
    );

String _shown() => [
  for (final name in [
    'LandingRoute',
    'DetailRoute',
    'ShellStartRoute',
    ..._tabNames,
  ])
    if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
].join(',');

String _state(RootStackRouter router) => [
  'shown ${_shown()}',
  'root ${router.stack.map((page) => page.routeData.name).join(' ')}',
  'url ${router.currentUrl}',
].join(', ');

// Starts the app, opens [path], saves, sets the tabs list to [after] and
// restores; answers what showed before and after.
Future<(String, String)> _saveAndRestore(
  WidgetTester tester,
  _Tabs kind,
  ValueNotifier<List<PageRouteInfo>> list,
  String path, {
  List<PageRouteInfo> after = const [_feed, _settings],
  bool pushDetail = false,
}) async {
  await tester.pumpWidget(RestorableRouterApp(() => _build(kind, list)));
  await tester.pumpAndSettle();
  unawaited(RestorableRouterApp.router.navigatePath(path));
  await tester.pumpAndSettle();
  if (pushDetail) {
    unawaited(RestorableRouterApp.router.push(const NamedRoute('DetailRoute')));
    await tester.pumpAndSettle();
  }
  final saved = _state(RestorableRouterApp.router);
  list.value = after;
  await tester.restartAndRestore();
  await tester.pumpAndSettle();
  return (saved, _state(RestorableRouterApp.router));
}

void main() {
  late ValueNotifier<List<PageRouteInfo>> list;
  setUp(() => list = ValueNotifier(const [_feed, _profile, _settings]));
  tearDown(() => list.dispose());

  for (final kind in _Tabs.values) {
    testWidgets('${kind.name}: a restore of the tabs page on a removed tab '
        'shows its first tab', (tester) async {
      final seen = await _saveAndRestore(tester, kind, list, '/home/profile');

      expect(tester.takeException(), isNull);
      expect(seen, (
        'shown ProfileTab, root LandingRoute HomeRoute, url /home/profile',
        'shown FeedTab, root LandingRoute HomeRoute, url /home/feed',
      ));
      // An entry for Landing and one for Home, as a restore of a tab still
      // listed gives.
      expect(RestorableRouterApp.router.navigationHistory.length, 2);
    });
  }

  testWidgets('A restore of the tabs page an app was launched at, on a '
      'removed tab, shows its first tab', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/home/profile';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      RestorableRouterApp(() => _build(.indexedStack, list)),
    );
    await tester.pumpAndSettle();
    final saved = _state(RestorableRouterApp.router);
    list.value = const [_feed, _settings];
    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (saved, _state(RestorableRouterApp.router)),
      (
        'shown ProfileTab, root LandingRoute HomeRoute, url /home/profile',
        'shown FeedTab, root LandingRoute HomeRoute, url /home/feed',
      ),
    );
  });

  testWidgets('A restore of the tabs page on a removed first tab shows the '
      'first tab left', (tester) async {
    list.value = const [_profile, _feed, _settings];

    final seen = await _saveAndRestore(
      tester,
      .indexedStack,
      list,
      '/home/profile',
    );

    expect(tester.takeException(), isNull);
    expect(
      seen.$2,
      'shown FeedTab, root LandingRoute HomeRoute, url /home/feed',
    );
  });

  testWidgets('A restore of the tabs page on a tab still listed shows that '
      'tab', (tester) async {
    final seen = await _saveAndRestore(
      tester,
      .indexedStack,
      list,
      '/home/settings',
      after: const [_feed, _profile, _settings],
    );

    expect(tester.takeException(), isNull);
    expect(seen, (
      'shown SettingsTab, root LandingRoute HomeRoute, url /home/settings',
      'shown SettingsTab, root LandingRoute HomeRoute, url /home/settings',
    ));
    expect(RestorableRouterApp.router.navigationHistory.length, 2);
  });

  testWidgets('A restore of a tabs page nested in another page, on a removed '
      'tab, shows its first tab', (tester) async {
    final seen = await _saveAndRestore(
      tester,
      .indexedStack,
      list,
      '/shell/home/profile',
    );

    expect(tester.takeException(), isNull);
    expect(seen, (
      'shown ProfileTab, root LandingRoute ShellRoute, url /shell/home/profile',
      'shown FeedTab, root LandingRoute ShellRoute, url /shell/home/feed',
    ));
  });

  testWidgets('A restore with a page over the tabs page on a removed tab '
      'keeps both', (tester) async {
    final seen = await _saveAndRestore(
      tester,
      .indexedStack,
      list,
      '/home/profile',
      pushDetail: true,
    );
    final router = RestorableRouterApp.router..pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(seen, (
      'shown DetailRoute, root LandingRoute HomeRoute DetailRoute, url /detail',
      'shown DetailRoute, root LandingRoute HomeRoute DetailRoute, url /detail',
    ));
    expect(
      _state(router),
      'shown FeedTab, root LandingRoute HomeRoute, url /home/feed',
    );
  });

  // Decision 1 of the batch: a link to a removed tab is turned down, also
  // the link an app is launched with. Dev 921fce58 showed Home on Feed.
  testWidgets('An app launched at a removed tab, with a page under the tabs '
      'page, shows that page', (tester) async {
    list.value = const [_feed, _settings];
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/home/profile';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = _build(.indexedStack, list);
    await pumpRouterConfigApp(tester, router.config());

    expect(tester.takeException(), isNull);
    expect(_state(router), 'shown LandingRoute, root LandingRoute, url /');
  });
}
