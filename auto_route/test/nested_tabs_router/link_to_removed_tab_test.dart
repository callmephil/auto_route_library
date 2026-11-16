import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// A link to a tab the app has removed from its tabs list, as a tab hidden by
// role, plan or feature flag, was taken as let in: off the web nothing
// changed and nobody was told, and on the web the address bar and urlState
// named the removed tab while another tab showed. Only the tabs router's own
// navigate reported a RouteNotFoundFailure. The owner decided that such a
// link is turned down on every platform.
// Setup: HomeRoute's children FeedTab, ProfileTab and SettingsTab stay in the
// router's config. The tabs list goes from Feed, Profile and Settings to
// Feed and Settings after Profile was opened, or never had Profile. The
// user is on Settings. Each kind of tabs widget.
// Steps: a path to /profile, a platform link to it, a root navigate to
// HomeRoute with ProfileTab, the app opened at the link, and the neighbors
// below.
// Was: the link's navigation was let in: no failure reached onFailure, the
// dialogs over the tabs closed, a link added entries to the app's own
// history, its query parameters went to the tab on screen, and an app opened
// at the link with a page under the tabs page showed the tabs page.
// Should: the page on screen, the active tab, the stacks and the url stay.
// onFailure hears a RouteNotFoundFailure, and the app's own call without
// one throws, as the tabs router's own navigate does.
// Native behavior this holds to: UITabBarController can select only a view
// controller in its viewControllers array, and an app that can't open a
// link returns false from its app delegate's open-url method and keeps what
// it shows; Android's NavController.handleDeepLink returns false for a
// destination the graph lacks, and nothing changes; on the web a canceled
// navigation keeps the document on screen and its url.
enum _Tabs { indexedStack, pageView, tabBar, builder }

enum _Way { navigatePath, link, rootNavigate }

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

// The tabs page shows [list], the tabs as the app lists them. With
// [hasLanding], the app starts on LandingRoute at '/' and the tabs page is
// at '/home'; otherwise the tabs page is the app's first page, at '/'.
RootStackRouter _build(
  _Tabs kind,
  ValueNotifier<List<PageRouteInfo>> list, {
  bool hasLanding = false,
  AutoRouteGuard? homeGuard,
}) => .build(
  routes: [
    if (hasLanding) _page('LandingRoute', '/'),
    NamedRouteDef(
      name: 'HomeRoute',
      path: hasLanding ? '/home' : '/',
      guards: [?homeGuard],
      builder: (_, _) => Scaffold(
        body: ValueListenableBuilder(
          valueListenable: list,
          builder: (_, routes, _) => _tabsOf(kind, routes),
        ),
      ),
      children: [
        for (final name in _tabNames)
          NamedRouteDef(
            name: name,
            path: name.replaceAll('Tab', '').toLowerCase(),
            builder: (_, _) => Center(child: Text(name)),
          ),
      ],
    ),
    _page('DetailRoute', '/detail'),
  ],
);

String _shown() => [
  for (final name in [..._tabNames, 'LandingRoute', 'DetailRoute'])
    if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
].join(',');

List<String> _names(RoutingController router) => [
  for (final data in router.stackData) data.name,
];

// What the user sees and the router holds: the page on screen, the active
// tab, the stacks of the tabs and of the root, and the url.
String _state(RootStackRouter router) {
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute');
  return [
    'shown ${_shown()}',
    if (tabs != null) 'tab ${tabs.activeIndex} ${tabs.current.name}',
    if (tabs != null) 'tabs ${_names(tabs).join(' ')}',
    'root ${_names(router).join(' ')}',
    'url ${router.currentUrl}',
  ].join(', ');
}

// Steps back until the app's own history can't; the urls it shows, the
// current one first.
Future<List<String>> _walkBack(
  WidgetTester tester,
  RootStackRouter router,
) async {
  final urls = [router.currentUrl];
  for (var i = 0; i < 10 && router.navigationHistory.canNavigateBack; i++) {
    router.back();
    await tester.pumpAndSettle();
    urls.add(router.currentUrl);
  }
  return urls;
}

// Opens the tabs page and the user's tabs: Feed, Profile and Settings, with
// Profile then removed from the list, when [removedLater]; else Feed and
// Settings of a list that never had Profile.
Future<RootStackRouter> _openOnSettings(
  WidgetTester tester,
  _Tabs kind,
  ValueNotifier<List<PageRouteInfo>> list, {
  required bool removedLater,
  AutoRouteGuard? homeGuard,
}) async {
  list.value = removedLater
      ? const [_feed, _profile, _settings]
      : const [_feed, _settings];
  final router = _build(kind, list, homeGuard: homeGuard);
  await pumpRouterConfigApp(tester, router.config());
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  if (removedLater) {
    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();
    expect(_shown(), 'ProfileTab');
    tabs.setActiveIndex(2);
    await tester.pumpAndSettle();
    list.value = const [_feed, _settings];
    await tester.pumpAndSettle();
  } else {
    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();
  }
  return router;
}

const _onSettings =
    'shown SettingsTab, tab 1 SettingsTab, tabs FeedTab SettingsTab, '
    'root HomeRoute, url /settings';

void main() {
  late ValueNotifier<List<PageRouteInfo>> list;

  setUp(() => list = ValueNotifier(const []));
  tearDown(() => list.dispose());

  for (final kind in _Tabs.values) {
    for (final removedLater in [true, false]) {
      final how = removedLater
          ? 'removed after it was opened'
          : 'never in the list';
      for (final way in _Way.values) {
        testWidgets('${kind.name}, $how: ${way.name} to the removed tab is '
            'turned down', (tester) async {
          final router = await _openOnSettings(
            tester,
            kind,
            list,
            removedLater: removedLater,
          );
          final atStart = _state(router);
          final failures = <NavigationFailure>[];

          switch (way) {
            case .navigatePath:
              unawaited(
                router.navigatePath('/profile', onFailure: failures.add),
              );
            case .link:
              await tester.binding.handlePushRoute('/profile');
            case .rootNavigate:
              unawaited(
                router.navigate(
                  const NamedRoute('HomeRoute', children: [_profile]),
                  onFailure: failures.add,
                ),
              );
          }
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect((atStart, _state(router)), (_onSettings, _onSettings));
          expect(router.urlState.url, '/settings');
          expect(
            failures.map((failure) => failure.runtimeType),
            way == .link ? isEmpty : [RouteNotFoundFailure],
          );
          // The removed tab's entry left with its tab: back goes to Feed.
          expect(await _walkBack(tester, router), ['/settings', '/feed']);
        });
      }
    }

    testWidgets('${kind.name}: the app opened at the removed tab, with a page '
        'under the tabs page, shows that page', (tester) async {
      list.value = const [_feed, _settings];
      final router = _build(kind, list, hasLanding: true);
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/home/profile';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      await pumpRouterConfigApp(tester, router.config());

      expect(tester.takeException(), isNull);
      expect(_state(router), 'shown LandingRoute, root LandingRoute, url /');
      expect(router.navigationHistory.length, 1);
    });

    testWidgets('${kind.name}: the app opened at the removed tab of its first '
        'page shows its first tab', (tester) async {
      list.value = const [_feed, _settings];
      final router = _build(kind, list);
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/profile';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      await pumpRouterConfigApp(tester, router.config());

      expect(tester.takeException(), isNull);
      expect(
        _state(router),
        'shown FeedTab, tab 0 FeedTab, tabs FeedTab SettingsTab, '
        'root HomeRoute, url /feed',
      );
      expect(router.navigationHistory.length, 1);
    });
  }

  testWidgets('A root navigate to the removed tab without onFailure throws, '
      'and the tab on screen stays', (tester) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );

    await expectLater(
      router.navigate<void>(
        const NamedRoute('HomeRoute', children: [_profile]),
      ),
      throwsA(isA<FlutterError>()),
    );
    await tester.pumpAndSettle();

    expect(_state(router), _onSettings);
  });

  testWidgets("The tabs router's own navigate to the removed tab reports it "
      'as before', (tester) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    final failures = <NavigationFailure>[];

    unawaited(
      router
          .innerRouterOf<TabsRouter>('HomeRoute')!
          .navigate(_profile, onFailure: failures.add),
    );
    await tester.pumpAndSettle();

    expect(_state(router), _onSettings);
    expect(failures.map((failure) => failure.runtimeType), [
      RouteNotFoundFailure,
    ]);
  });

  testWidgets('A link to the removed tab with query parameters leaves the '
      "tabs' query parameters alone", (tester) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

    await tester.binding.handlePushRoute('/profile?ref=mail');
    await tester.pumpAndSettle();

    expect(_state(router), _onSettings);
    expect(tabs.current.queryParams.rawMap, isEmpty);
  });

  testWidgets('A link to the removed tab keeps the dialog open over the tabs', (
    tester,
  ) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    showDialog<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Draft')),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePushRoute('/profile');
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsOneWidget);
    expect(router.currentUrl, '/settings');
  });

  testWidgets('A path to the removed tab keeps the page over the tabs page', (
    tester,
  ) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    unawaited(router.push(const NamedRoute('DetailRoute')));
    await tester.pumpAndSettle();
    final failures = <NavigationFailure>[];

    unawaited(router.navigatePath('/profile', onFailure: failures.add));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'DetailRoute']);
    expect(_shown(), 'DetailRoute');
    expect(router.currentUrl, '/detail');
    expect(failures.map((failure) => failure.runtimeType), [
      RouteNotFoundFailure,
    ]);
  });

  for (final answersAtOnce in [true, false]) {
    final guardHow = answersAtOnce ? 'answers at once' : 'waits';
    testWidgets('A link to the removed tab past a guard of the tabs page that '
        '$guardHow and lets it in is turned down', (tester) async {
      final guard = HeldGuard(mode: .answersYes);
      final router = await _openOnSettings(
        tester,
        .indexedStack,
        list,
        removedLater: true,
        homeGuard: guard,
      );
      if (!answersAtOnce) guard.holdCall();

      await tester.binding.handlePushRoute('/profile');
      await tester.pump();
      if (!answersAtOnce) {
        expect(_shown(), 'SettingsTab');
        await guard.last.allow();
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_state(router), _onSettings);
      guard.answerYes();
      expect(await _walkBack(tester, router), ['/settings', '/feed']);
    });
  }

  testWidgets('A tab change called in the same turn as a path to the removed '
      'tab shows its tab', (tester) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    final failures = <NavigationFailure>[];

    unawaited(router.navigatePath('/profile', onFailure: failures.add));
    unawaited(router.navigatePath('/feed'));
    await tester.pumpAndSettle();

    expect(failures.map((failure) => failure.runtimeType), [
      RouteNotFoundFailure,
    ]);
    expect(_shown(), 'FeedTab');
    expect(router.currentUrl, '/feed');
  });

  // replacePath puts a new tabs page in the place of the one on screen,
  // which takes over its screen and its tabs: the caller's onFailure hears
  // what those tabs turn down, as it does for pushPath and navigatePath.
  testWidgets('replacePath to the removed tab keeps the tab and reports it', (
    tester,
  ) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    final failures = <NavigationFailure>[];

    unawaited(router.replacePath<Object?>('/profile', onFailure: failures.add));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_state(router), _onSettings);
    expect(failures.map((failure) => failure.runtimeType), [
      RouteNotFoundFailure,
    ]);
  });

  testWidgets('A path to a tab still in the list shows it', (tester) async {
    final router = await _openOnSettings(
      tester,
      .indexedStack,
      list,
      removedLater: true,
    );
    final failures = <NavigationFailure>[];

    unawaited(router.navigatePath('/feed', onFailure: failures.add));
    await tester.pumpAndSettle();

    expect(failures, isEmpty);
    expect(_shown(), 'FeedTab');
    expect(router.currentUrl, '/feed');
  });

  testWidgets("The app's navigate to the tabs page on the removed tab, from "
      'another page, takes the tabs page back and reports it', (tester) async {
    list.value = const [_feed, _settings];
    final router = _build(.indexedStack, list, hasLanding: true);
    await pumpRouterConfigApp(tester, router.config());
    final failures = <NavigationFailure>[];

    unawaited(
      router.navigate(
        const NamedRoute('HomeRoute', children: [_profile]),
        onFailure: failures.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_state(router), 'shown LandingRoute, root LandingRoute, url /');
    expect(failures.map((failure) => failure.runtimeType), [
      RouteNotFoundFailure,
    ]);
    expect(router.navigationHistory.length, 1);
  });

  testWidgets('A path to the removed tab of tabs inside a tab is turned '
      'down', (tester) async {
    final inner = ValueNotifier<List<PageRouteInfo>>(const [
      NamedRoute('InboxTab'),
      NamedRoute('SentTab'),
    ]);
    addTearDown(inner.dispose);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(routes: [_feed, NamedRoute('MailTab')]),
          ),
          children: [
            _page('FeedTab', 'feed'),
            NamedRouteDef(
              name: 'MailTab',
              path: 'mail',
              builder: (_, _) => ValueListenableBuilder(
                valueListenable: inner,
                builder: (_, routes, _) => AutoTabsRouter(routes: routes),
              ),
              children: [
                for (final name in ['InboxTab', 'SentTab', 'DraftsTab'])
                  _page(name, name.replaceAll('Tab', '').toLowerCase()),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.navigatePath('/mail/sent'));
    await tester.pumpAndSettle();
    final atStart = router.currentUrl;
    final failures = <NavigationFailure>[];

    unawaited(router.navigatePath('/mail/drafts', onFailure: failures.add));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SentTab'), findsOneWidget);
    expect((atStart, router.currentUrl), ('/mail/sent', '/mail/sent'));
    expect(failures.map((failure) => failure.runtimeType), [
      RouteNotFoundFailure,
    ]);
  });
}
