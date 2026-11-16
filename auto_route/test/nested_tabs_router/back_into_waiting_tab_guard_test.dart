@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// Off the web, back() into a tab whose guard waits, then lets the tab in,
// left two extra entries in the app's own history, so the next back()
// reopened the tab just left. A guard that answers at once, one that
// rejects, and a stack page whose guard waits were right.
// The cause: the tabs router's navigation answered at once, before the
// tab's guard did, so the history took the step back for refused, put the
// left tab's entry back, and then added the tab let in as a new entry.
// Setup: Home, then Tabs with Feed, Mail (guarded) and Settings, shown in
// that order. Each kind of tabs widget.
// Steps: on Settings, call back. Mail's guard waits, then lets Mail in.
// Then call back until the history can't.
// Was: 5 entries in the history, and the walk back went from Mail to
// Settings, Mail, Feed and Home.
// Should: 3 entries, and the walk back from Mail to Feed and Home, as when
// the guard answers at once.
// Native behavior this holds to: a step back is one step. MDN,
// History.back(): it moves back one page in the session history, as
// history.go(-1) does, and completes at popstate; on Android the back action
// pops the current activity and destroys it, so the next back shows the one
// before it, never the one just left.
enum _Tabs { indexedStack, pageView, tabBar, builder }

Widget _tabsOf(_Tabs kind) {
  const routes = [
    NamedRoute<Object?>('FeedTab'),
    NamedRoute<Object?>('MailTab'),
    NamedRoute<Object?>('SettingsTab'),
  ];
  return switch (kind) {
    .indexedStack => const AutoTabsRouter(routes: routes),
    .pageView => const AutoTabsRouter.pageView(routes: routes),
    .tabBar => const AutoTabsRouter.tabBar(routes: routes),
    .builder => AutoTabsRouter.builder(
      routes: routes,
      builder: (_, children, tabs) =>
          IndexedStack(index: tabs.activeIndex, children: children),
    ),
  };
}

NamedRouteDef _tab(String name, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: name.replaceAll('Tab', '').toLowerCase(),
  guards: [?guard],
  builder: (_, _) => Center(child: Text(name)),
);

RootStackRouter _router(_Tabs kind, AutoRouteGuard guard) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
    ),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => Scaffold(body: _tabsOf(kind)),
      children: [
        _tab('FeedTab'),
        _tab('MailTab', guard: guard),
        _tab('SettingsTab'),
      ],
    ),
  ],
);

String _state(RootStackRouter router) {
  final tabs = router.innerRouterOf<TabsRouter>('TabsRoute');
  return [
    router.stack.map((page) => page.routeData.name).join(' '),
    if (tabs != null) 'tab ${tabs.activeIndex}',
    'url ${router.currentUrl}',
    'history ${router.navigationHistory.length}',
  ].join(', ');
}

// Steps back until the history can't, the guard answering at once; the urls
// it shows, starting with the current one.
Future<List<String>> _walk(
  WidgetTester tester,
  RootStackRouter router,
  HeldGuard guard,
) async {
  guard.answerYes();
  final urls = [router.currentUrl];
  for (var i = 0; i < 10 && router.navigationHistory.canNavigateBack; i++) {
    router.back();
    await tester.pumpAndSettle();
    urls.add(router.currentUrl);
  }
  return urls;
}

// Opens Tabs and shows Feed, Mail and Settings, in that order, Mail's guard
// answering yes at once; then makes the guard hold its next call.
Future<RootStackRouter> _openTabs(
  WidgetTester tester,
  _Tabs kind,
  HeldGuard guard,
) async {
  guard.answerYes();
  final router = _router(kind, guard);
  await pumpRouterApp(tester, router);
  unawaited(router.push(const NamedRoute('TabsRoute')));
  await tester.pumpAndSettle();
  final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
  for (final index in [1, 2]) {
    tabs.setActiveIndex(index);
    await tester.pumpAndSettle();
  }
  expect(
    _state(router),
    'HomeRoute TabsRoute, tab 2, url /tabs/settings, history 4',
  );
  guard
    ..clear()
    ..holdCall();
  return router;
}

const _onMail = 'HomeRoute TabsRoute, tab 1, url /tabs/mail, history 3';
const _onSettings = 'HomeRoute TabsRoute, tab 2, url /tabs/settings, history 4';

void main() {
  for (final kind in _Tabs.values) {
    for (final mode in [HeldGuardMode.holdsCall, HeldGuardMode.returnsAtOnce]) {
      final how = mode == .holdsCall
          ? 'awaits in its call'
          : 'answers after its call';
      testWidgets('${kind.name}: back() into a tab whose guard $how, then '
          'lets it in, steps back once', (tester) async {
        final guard = HeldGuard();
        final router = await _openTabs(tester, kind, guard);
        guard.mode = mode;

        router.back();
        await tester.pumpAndSettle();
        expect(find.text('SettingsTab').hitTestable(), findsOneWidget);
        await guard.last.allow();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_state(router), _onMail);
        expect(await _walk(tester, router, guard), [
          '/tabs/mail',
          '/tabs/feed',
          '/',
        ]);
      });
    }

    testWidgets('${kind.name}: back() into a tab whose guard waits, then '
        'rejects, keeps the tab and its entry', (tester) async {
      final guard = HeldGuard();
      final router = await _openTabs(tester, kind, guard);

      router.back();
      await tester.pumpAndSettle();
      await guard.last.reject();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_state(router), _onSettings);
      expect(await _walk(tester, router, guard), [
        '/tabs/settings',
        '/tabs/mail',
        '/tabs/feed',
        '/',
      ]);
    });
  }

  testWidgets('back() into a tab whose guard answers at once steps back once', (
    tester,
  ) async {
    final guard = HeldGuard();
    final router = await _openTabs(tester, .indexedStack, guard);
    guard.answerYes();

    router.back();
    await tester.pumpAndSettle();

    expect(_state(router), _onMail);
    expect(await _walk(tester, router, guard), [
      '/tabs/mail',
      '/tabs/feed',
      '/',
    ]);
  });

  testWidgets('back() into a tab whose guard waits, answered in the same turn '
      'as the back, steps back once', (tester) async {
    final guard = HeldGuard();
    final router = await _openTabs(tester, .indexedStack, guard);
    guard.mode = .returnsAtOnce;

    router.back();
    unawaited(guard.last.allow());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_state(router), _onMail);
    expect(await _walk(tester, router, guard), [
      '/tabs/mail',
      '/tabs/feed',
      '/',
    ]);
  });

  testWidgets('back() into a tab whose guard waits, while the user picks '
      'another tab, shows the tab picked', (tester) async {
    final guard = HeldGuard();
    final router = await _openTabs(tester, .indexedStack, guard);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;

    router.back();
    await tester.pumpAndSettle();
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();
    await guard.last.allow();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tabs.current.name, 'FeedTab');
    expect(router.currentUrl, '/tabs/feed');
  });

  testWidgets('back() into a tab of tabs inside a tab, whose guard waits, then '
      'lets it in, steps back once', (tester) async {
    final guard = HeldGuard(mode: .answersYes);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('FeedTab'),
                NamedRoute<Object?>('MailTab'),
              ],
            ),
          ),
          children: [
            _tab('FeedTab'),
            NamedRouteDef(
              name: 'MailTab',
              path: 'mail',
              builder: (_, _) => const AutoTabsRouter(
                routes: [
                  NamedRoute<Object?>('InboxTab'),
                  NamedRoute<Object?>('SentTab'),
                  NamedRoute<Object?>('DraftsTab'),
                ],
              ),
              children: [
                _tab('InboxTab'),
                _tab('SentTab', guard: guard),
                _tab('DraftsTab'),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    for (final path in ['/mail/inbox', '/mail/sent', '/mail/drafts']) {
      unawaited(router.navigatePath(path));
      await tester.pumpAndSettle();
    }
    expect(router.navigationHistory.length, 4);
    guard
      ..clear()
      ..holdCall();

    router.back();
    await tester.pumpAndSettle();
    await guard.last.allow();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/mail/sent');
    expect(router.navigationHistory.length, 3);
    expect(await _walk(tester, router, guard), [
      '/mail/sent',
      '/mail/inbox',
      '/feed',
    ]);
  });
}
