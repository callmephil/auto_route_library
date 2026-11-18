import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, the browser's back button after pushAll in a tab not on screen
// shows each page once and never moves the browser forward
// (callmephil/auto_route_library#21).
//
// Steps: on Home, open Tabs on tab One; select tab Two; call
// pushAll([X1, Y1]) on the router of tab One, which is not on screen; select
// tab One, which shows Y1. Press the browser's back button until Home, then
// its forward button until Y1.
// Was: 6 back presses showed X1, Two, OneIndex, Two, OneIndex and Home, and
// the third moved the browser forward. That press landed on the entry of
// OneIndex while tab Two was on screen, and the app first took X1 off tab
// One. The url that removal reported named the tab on screen, Two, and the
// history took it for a new entry after the entry the browser had landed
// on: it moved the browser forward onto the entry of Two and wrote OneIndex
// after it, which dropped the entries ahead. Forward then stopped on
// OneIndex. A jump of two entries back lost the entries ahead in the same
// way, onto a page in a tab not on screen, onto a page under the page on
// top, or onto an earlier url of that page.
// Should: 4 back presses show X1, Two, OneIndex, then Home, and forward
// walks the same entries up to Y1. No press adds or changes an entry, and
// no back press moves the browser forward.
//
// Native behavior this holds to: Flutter's Navigator.pop in the router of
// the tab closes Y1, then X1. In the HTML standard's session history, a
// back or forward traversal moves to another entry and adds or changes
// none.
//
// The same walk runs in a real browser in
// test/web/back_after_push_all_in_hidden_tab_web_test.dart, and in the
// example app in
// example.old/integration_test/back_after_push_all_in_hidden_tab_test.dart.

// The app of the issue: Home, then Tabs with the tabs One and Two, each with
// a nested router, One with OneIndex, X1, Y1 and Z1, Two with TwoIndex. Mail
// has a nested router with Inbox and Message, which B covers, and Item
// shows its query params in its url.
class _TabsRouter extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser _browser;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    // The test's clock runs through every animation at once; the browser
    // of a test lands late, never too late.
    landingLimit: const Duration(hours: 1),
  );

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [
          NamedRoute<Object?>('OneRoute'),
          NamedRoute<Object?>('TwoRoute'),
        ],
        builder: (_, child) => child,
      ),
      children: [
        NamedRouteDef(
          name: 'OneRoute',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OneIndexRoute', ''),
            _page('X1Route', 'x'),
            _page('Y1Route', 'y'),
            _page('Z1Route', 'z'),
          ],
        ),
        NamedRouteDef(
          name: 'TwoRoute',
          path: 'two',
          builder: (_, _) => const AutoRouter(),
          children: [_page('TwoIndexRoute', '')],
        ),
      ],
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const AutoRouter(),
      children: [_page('InboxRoute', ''), _page('MessageRoute', ':id')],
    ),
    _page('ItemRoute', '/item'),
    _page('BRoute', '/b'),
  ];
}

// The app of a test and the browser it writes.
class _App {
  new(this.tester) {
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final router = _TabsRouter(browser);

  TabsRouter get _tabs => router.innerRouterOf('TabsRoute')!;

  // The router of tab One.
  StackRouter get one => _tabs.innerRouterOf('OneRoute')!;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // What the app asked of the browser since [mark].
  Iterable<String> get askedSinceMark => browser.asked.skip(_mark);
  int _mark = 0;

  void mark() => _mark = browser.asked.length;

  Future<void> start() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
  }

  // Makes [call], then waits until the browser holds what the app shows.
  Future<void> run(void Function() call) async {
    call();
    await browser.settle(tester);
  }

  Future<void> push(PageRouteInfo route) =>
      run(() => unawaited(router.push(route)));

  Future<void> selectTab(int index) => run(() => _tabs.setActiveIndex(index));

  // The page shown after each press of [press], at most [limit] presses,
  // until it has no entry to go to.
  Future<List<String>> walk(bool Function() press, int limit) async {
    final shownAfter = <String>[];
    for (var i = 0; i < limit && press(); i++) {
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }
}

void main() {
  // The steps of the issue, and the same with three pages.
  for (final (hidden, entries, backWalk) in [
    (
      ['X1Route', 'Y1Route'],
      '/ /tabs/one /tabs/two /tabs/one/x >/tabs/one/y',
      [
        'X1Route /tabs/one/x',
        'TwoIndexRoute /tabs/two',
        'OneIndexRoute /tabs/one',
        'HomeRoute /',
      ],
    ),
    (
      ['X1Route', 'Y1Route', 'Z1Route'],
      '/ /tabs/one /tabs/two /tabs/one/x /tabs/one/y >/tabs/one/z',
      [
        'Y1Route /tabs/one/y',
        'X1Route /tabs/one/x',
        'TwoIndexRoute /tabs/two',
        'OneIndexRoute /tabs/one',
        'HomeRoute /',
      ],
    ),
  ]) {
    testWidgets('After pushAll of ${hidden.join(', ')} in a tab not on '
        'screen, back shows each page once, and forward walks the same '
        'entries', (tester) async {
      final app = _App(tester);
      await app.start();
      await app.push(const NamedRoute<Object?>('TabsRoute'));
      await app.selectTab(1);
      await app.run(
        () => unawaited(
          app.one.pushAll([
            for (final name in hidden) NamedRoute<Object?>(name),
          ]),
        ),
      );
      await app.selectTab(0);
      final top = app.shown;
      // Read before the walk: the entries the browser holds on the top page.
      final heldOnTop = app.browser.held;
      app.mark();

      expect(await app.walk(app.browser.didPressBack, 8), backWalk);
      // Each press landed on the entry before, and the app asked nothing of
      // the browser.
      expect(app.askedSinceMark, isEmpty);
      expect(app.browser.held, '>${entries.replaceFirst('>', '')}');
      app.mark();

      expect(await app.walk(app.browser.didPressForward, 8), [
        ...backWalk.reversed.skip(1),
        top,
      ]);
      // Forward wrote nothing: on the top page again, the browser holds
      // what it held there before the walk. The press onto the entry of Two
      // may step the browser back and forth once, while the tabs page opened
      // again builds the router of Two: a url report of the tab on screen
      // drops the entry landed on for a moment, as in
      // callmephil/auto_route_library#22.
      expect(
        app.askedSinceMark.where((call) => !call.startsWith('go ')),
        isEmpty,
      );
      expect((heldOnTop, app.browser.held), (entries, entries));
    });
  }

  // Steps: on Home, open Tabs on tab One; push X1 in tab One; select tab
  // Two. Go two entries back at once, onto the entry of OneIndex, then
  // forward.
  testWidgets('A jump of two entries back onto a page in a tab not on '
      'screen keeps the entries ahead', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.push(const NamedRoute<Object?>('TabsRoute'));
    await app.run(
      () => unawaited(app.one.push(const NamedRoute<Object?>('X1Route'))),
    );
    await app.selectTab(1);
    expect(app.browser.held, '/ /tabs/one /tabs/one/x >/tabs/two');
    app.mark();

    expect(await app.walk(() => app.browser.didJump(-2), 1), [
      'OneIndexRoute /tabs/one',
    ]);
    expect(app.browser.held, '/ >/tabs/one /tabs/one/x /tabs/two');
    expect(await app.walk(app.browser.didPressForward, 3), [
      'X1Route /tabs/one/x',
      'TwoIndexRoute /tabs/two',
    ]);
    expect(app.askedSinceMark, isEmpty);
  });

  // Steps: on Home, open Mail, then the messages 1 and 2 in its router, then
  // B over Mail. Go two entries back at once, onto the entry of message 1,
  // then forward.
  testWidgets('A jump of two entries back onto a page under the page on '
      'top keeps the entries ahead', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.push(const NamedRoute<Object?>('MailRoute'));
    final mail = app.router.innerRouterOf<StackRouter>('MailRoute')!;
    for (final id in ['1', '2']) {
      await app.run(
        () => unawaited(
          mail.push(NamedRoute<Object?>('MessageRoute', params: {'id': id})),
        ),
      );
    }
    await app.push(const NamedRoute<Object?>('BRoute'));
    expect(app.browser.held, '/ /mail /mail/1 /mail/2 >/b');
    app.mark();

    expect(await app.walk(() => app.browser.didJump(-2), 1), [
      'MessageRoute /mail/1',
    ]);
    expect(app.browser.held, '/ /mail >/mail/1 /mail/2 /b');
    expect(await app.walk(app.browser.didPressForward, 3), [
      'MessageRoute /mail/2',
      'BRoute /b',
    ]);
    expect(app.askedSinceMark, isEmpty);
  });

  // Steps: on Home, open Item at '/item?id=1', navigate to it at
  // '/item?id=2', which changes its url in place, then open B. Go two
  // entries back at once, onto the entry of Item at '/item?id=1', then
  // forward.
  testWidgets('A jump of two entries back onto an earlier url of the page '
      'under the page on top keeps the entries ahead', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.push(
      const NamedRoute<Object?>('ItemRoute', queryParams: {'id': '1'}),
    );
    await app.run(
      () => unawaited(
        app.router.navigate(
          const NamedRoute<Object?>('ItemRoute', queryParams: {'id': '2'}),
        ),
      ),
    );
    await app.push(const NamedRoute<Object?>('BRoute'));
    expect(app.browser.held, '/ /item?id=1 /item?id=2 >/b');
    app.mark();

    expect(await app.walk(() => app.browser.didJump(-2), 1), [
      'ItemRoute /item?id=1',
    ]);
    expect(app.router.urlState.url, '/item?id=1');
    expect(app.browser.held, '/ >/item?id=1 /item?id=2 /b');
    expect(await app.walk(app.browser.didPressForward, 3), [
      'ItemRoute /item?id=2',
      'BRoute /b',
    ]);
    expect(app.askedSinceMark, isEmpty);
  });

  // The control, right before the fix too: a page the app itself takes off
  // a tab not on screen, with no landing to follow, loses its entry, and
  // the browser steps back over it and writes the tab on screen again.
  testWidgets('removeLast in a tab not on screen drops the entry of the page '
      'it closes', (tester) async {
    final app = _App(tester);
    await app.start();
    await app.push(const NamedRoute<Object?>('TabsRoute'));
    await app.run(
      () => unawaited(
        app.one.pushAll(const [
          NamedRoute<Object?>('X1Route'),
          NamedRoute<Object?>('Y1Route'),
        ]),
      ),
    );
    await app.selectTab(1);
    expect(app.browser.held, '/ /tabs/one /tabs/one/x /tabs/one/y >/tabs/two');
    app.mark();

    await app.run(() => app.one.removeLast());

    expect(app.askedSinceMark, ['go -2', 'push /tabs/two']);
    expect(app.browser.held, '/ /tabs/one /tabs/one/x >/tabs/two');
    expect(await app.walk(app.browser.didPressBack, 4), [
      'X1Route /tabs/one/x',
      'OneIndexRoute /tabs/one',
      'HomeRoute /',
    ]);
  });
}
