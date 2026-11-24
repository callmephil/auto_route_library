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
// The cause: the tabs router's navigation answers once the tab change has
// started, before the tab's guard has answered, so the history took the
// step back for refused, put the left tab's entry back, and then added the
// tab let in as a new entry. The history now hears when its step back is
// let in, also after back() has ended, and then takes the step after all.
// A first fix, which made the tabs' navigation wait for the guard, stopped
// back() for good behind a guard that never answers, lost a tab's entry
// behind a guard that shows its sign-in page and says no, and made the
// app's own awaited navigate into such a tab wait: the neighbors below.
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
      name: 'LoginRoute',
      path: '/login',
      builder: (_, _) => const Scaffold(body: Text('LoginRoute')),
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

// What the code that called a navigation has heard so far.
class _Caller {
  new(Future<Object?> future) {
    unawaited(future.then((_) => _isDone = true));
  }

  bool _isDone = false;

  @override
  String toString() => _isDone ? 'done' : 'waits';
}

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

  testWidgets('back() into a tab whose guard never answers leaves back() '
      'working', (tester) async {
    final guard = HeldGuard();
    final router = await _openTabs(tester, .indexedStack, guard);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
    guard.answerNothing();

    router.back();
    await tester.pumpAndSettle();
    final seen = [_state(router)];
    tabs.setActiveIndex(0);
    await tester.pumpAndSettle();
    seen.add(_state(router));
    router.back();
    await tester.pumpAndSettle();
    seen.add(_state(router));

    expect(tester.takeException(), isNull);
    expect(router.navigationHistory.canNavigateBack, isTrue);
    expect(seen, [
      _onSettings,
      'HomeRoute TabsRoute, tab 0, url /tabs/feed, history 5',
      _onSettings,
    ]);
  });

  testWidgets('back() into a tab whose guard shows its sign-in page and says '
      'no keeps the tab and its entry', (tester) async {
    final guard = HeldGuard();
    final router = await _openTabs(tester, .indexedStack, guard);

    router.back();
    await tester.pumpAndSettle();
    await guard.last.redirect(const NamedRoute('LoginRoute'));
    await tester.pumpAndSettle();
    router.pop();
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

  testWidgets('back() into a tab whose guard shows its sign-in page until it '
      'lets the tab in steps back once', (tester) async {
    final guard = HeldGuard(mode: .returnsAtOnce);
    final router = await _openTabs(tester, .indexedStack, guard);
    guard.answerNothing();

    router.back();
    await tester.pumpAndSettle();
    final resolver = guard.last.resolver;
    unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
    await tester.pumpAndSettle();
    resolver.next();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_state(router), _onMail);
    expect(await _walk(tester, router, guard), [
      '/tabs/mail',
      '/tabs/feed',
      '/',
    ]);
  });

  // The app's own navigation into a tab answers once the tab change has
  // started, as before, whatever its guard does: code after an await on it
  // goes on.
  for (final way in ['root navigate', 'navigatePath', 'tabs.navigate']) {
    testWidgets('$way into a tab whose guard never answers answers at once', (
      tester,
    ) async {
      final guard = HeldGuard();
      final router = await _openTabs(tester, .indexedStack, guard);
      final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
      guard.answerNothing();

      final caller = _Caller(switch (way) {
        'root navigate' => router.navigate(
          const NamedRoute('TabsRoute', children: [NamedRoute('MailTab')]),
        ),
        'navigatePath' => router.navigatePath('/tabs/mail'),
        _ => tabs.navigate(const NamedRoute('MailTab')),
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect('$caller', 'done');
      expect(_state(router), _onSettings);
    });
  }

  // The guard of MailTab holds the step. ComposeRoute is open in the tab, so
  // no step back asks its guard (callmephil/auto_route_library#42).
  testWidgets('back() into a page of a tab whose guard waits, then lets it '
      'in, steps back once', (tester) async {
    final tabGuard = HeldGuard(mode: .answersYes);
    final guard = HeldGuard(mode: .answersYes);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('FeedTab'),
                NamedRoute<Object?>('MailTab'),
                NamedRoute<Object?>('SettingsTab'),
              ],
            ),
          ),
          children: [
            _tab('FeedTab'),
            NamedRouteDef(
              name: 'MailTab',
              path: 'mail',
              guards: [tabGuard],
              builder: (_, _) => const AutoRouter(),
              children: [
                _tab('InboxRoute').copyWith(path: ''),
                _tab('ComposeRoute', guard: guard).copyWith(path: 'compose'),
              ],
            ),
            _tab('SettingsTab'),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    for (final path in ['/mail/compose', '/settings']) {
      unawaited(router.navigatePath(path));
      await tester.pumpAndSettle();
    }
    final atStart = (router.currentUrl, router.navigationHistory.length);
    guard.clear();
    tabGuard
      ..clear()
      ..holdCall();

    router.back();
    await tester.pumpAndSettle();
    await tabGuard.last.allow();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(atStart, ('/settings', 4));
    expect(router.currentUrl, '/mail/compose');
    expect(await _walk(tester, router, tabGuard), [
      '/mail/compose',
      '/mail',
      '/feed',
    ]);
    expect(guard.askCount, 0);
  });

  // The late step is its own: it changes the history only when it lands on
  // the page gone back to, and only while the entry back() put back is
  // still where back() put it. As on dev in both cases below. In the first,
  // the guard of MailTab holds the step, and the user's pick calls it off.
  testWidgets('back() into a page of a tab whose guard waits, while the user '
      'picks another tab, keeps the tab left on the way back', (tester) async {
    final tabGuard = HeldGuard(mode: .answersYes);
    final guard = HeldGuard(mode: .answersYes);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('FeedTab'),
                NamedRoute<Object?>('MailTab'),
                NamedRoute<Object?>('SettingsTab'),
              ],
            ),
          ),
          children: [
            _tab('FeedTab'),
            NamedRouteDef(
              name: 'MailTab',
              path: 'mail',
              guards: [tabGuard],
              builder: (_, _) => const AutoRouter(),
              children: [
                _tab('InboxRoute').copyWith(path: ''),
                _tab('ComposeRoute', guard: guard).copyWith(path: 'compose'),
              ],
            ),
            _tab('SettingsTab'),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    for (final path in ['/mail/compose', '/settings']) {
      unawaited(router.navigatePath(path));
      await tester.pumpAndSettle();
    }
    guard.clear();
    tabGuard
      ..clear()
      ..holdCall();

    router.back();
    await tester.pumpAndSettle();
    router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(0);
    await tester.pumpAndSettle();
    await tabGuard.last.allow();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/feed');
    expect(await _walk(tester, router, tabGuard), [
      '/feed',
      '/settings',
      '/mail/compose',
      '/mail',
      '/feed',
    ]);
    expect(guard.askCount, 0);
  });

  testWidgets('back() into a tab whose guard waits, while the app pushes a '
      "page in the tab left, keeps that tab's first page on the way back", (
    tester,
  ) async {
    final guard = HeldGuard(mode: .answersYes);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('FeedTab'),
                NamedRoute<Object?>('MailTab'),
                NamedRoute<Object?>('SettingsTab'),
              ],
            ),
          ),
          children: [
            _tab('FeedTab'),
            _tab('MailTab', guard: guard),
            NamedRouteDef(
              name: 'SettingsTab',
              path: 'settings',
              builder: (_, _) => const AutoRouter(),
              children: [
                _tab('SettingsMain').copyWith(path: ''),
                _tab('SettingsDetail').copyWith(path: 'detail'),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
    for (final index in [1, 2]) {
      tabs.setActiveIndex(index);
      await tester.pumpAndSettle();
    }
    guard
      ..clear()
      ..holdCall();

    router.back();
    await tester.pumpAndSettle();
    unawaited(
      tabs.stackRouterOfIndex(2)!.push(const NamedRoute('SettingsDetail')),
    );
    await tester.pumpAndSettle();
    await guard.last.allow();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/mail');
    expect(await _walk(tester, router, guard), [
      '/mail',
      '/settings/detail',
      '/settings',
      '/mail',
      '/feed',
    ]);
  });
}
