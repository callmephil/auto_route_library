import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, the browser's forward button walks the same entries that its
// back button walked down, also after the back button closed a tabs page.
// It changes none of them (callmephil/auto_route_library#22).
//
// Steps: on Home, open Tabs on tab One. In the nested router of One, call
// pushAll with X1 and Y1. Select tab Two, then tab One. In One, call
// replaceAll with Z1. The browser holds /, /tabs/two and /tabs/one/z. Press
// the browser's back button two times: Two, then Home, and the tabs page
// closes. Press the forward button until nothing is ahead.
// Was: the second forward press showed Z1 over OneIndex on a fourth entry.
// The app reopens the tabs page on tab Two, and the entry of Z1 opens tab
// One, never built in the new tabs page, before it shows. Two url reports
// came before Z1 was on, and the web history took each for a navigation.
// First the nested router of One, built off the screen, reported the url of
// the tab on screen, /tabs/two, so the browser stepped back to the entry of
// Two. Then tab One showed with its first page, OneIndex, a step before Z1
// went on over it. The browser then held /, /tabs/two, /tabs/one and
// /tabs/one/z, and the entries ahead of a forward press were lost.
// Should: the second forward press shows Z1 on the third entry, which is
// /tabs/one/z. The forward walk shows Two and then Z1. The browser holds the
// entries it held before the back walk, and the app asks it for no write
// and no step. This holds also with a guard on every page of the app, whose
// nested routers then put their first pages on after the frame that builds
// them. And a forward press onto the first page of a tab never built moves
// the browser nowhere: before, it moved the browser back and forward again.
//
// Native behavior this holds to: the HTML standard's session history, where
// a forward traversal moves to a later entry and changes none. Only
// history.pushState removes the entries ahead.
//
// The same walk runs in a real browser in
// test/web/forward_after_tabs_page_closes_web_test.dart, and in the example
// app in example.old/integration_test/forward_after_tabs_page_closes_test.dart.

// The app of the issue: Home, then Tabs with the tabs One and Two, each
// with a nested router. With [hasAppGuard], a guard of the app's that lets
// every page in, as a sign-in check does once the user is in.
class _TabsRouter extends RootStackRouter {
  new(this._browser, {required this.hasAppGuard});

  final TestHistoryBrowser _browser;
  final bool hasAppGuard;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    // The test's clock runs through every animation at once; the browser
    // of a test lands late, never too late.
    landingLimit: const Duration(hours: 1),
  );

  @override
  late final List<AutoRouteGuard> guards = [
    if (hasAppGuard) AutoRouteGuard.simple((resolver, _) => resolver.next()),
  ];

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
  ];
}

// The app of a test, on Tabs over Home.
class _App {
  new(this.tester, {bool hasAppGuard = false}) {
    router = _TabsRouter(browser, hasAppGuard: hasAppGuard);
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _TabsRouter router;

  TabsRouter get _tabs => router.innerRouterOf('TabsRoute')!;

  StackRouter get _one => _tabs.innerRouterOf('OneRoute')!;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  Future<void> openTabs() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await browser.settle(tester);
  }

  Future<void> selectTab(int index) async {
    _tabs.setActiveIndex(index);
    await browser.settle(tester);
  }

  Future<void> pushAllX1Y1() async {
    unawaited(
      _one.pushAll(const [
        NamedRoute<Object?>('X1Route'),
        NamedRoute<Object?>('Y1Route'),
      ]),
    );
    await browser.settle(tester);
  }

  Future<void> replaceAllZ1() async {
    unawaited(_one.replaceAll(const [NamedRoute<Object?>('Z1Route')]));
    await browser.settle(tester);
  }

  // The steps of the issue, up to Z1.
  Future<void> openZ1() async {
    await openTabs();
    await pushAllX1Y1();
    await selectTab(1);
    await selectTab(0);
    await replaceAllZ1();
  }

  // The page shown after each press of [press] until it has no entry to go
  // to, at most [limit] presses.
  Future<List<String>> walk(bool Function() press, int limit) async {
    final shownAfter = <String>[];
    for (var i = 0; i < limit && press(); i++) {
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }

  // What the app asked of the browser since [from] calls were asked.
  Iterable<String> askedSince(int from) => browser.asked.skip(from);
}

// The entries the browser holds on Z1, after the steps of the issue.
const _onZ1 = '/ /tabs/two >/tabs/one/z';

void main() {
  for (final hasAppGuard in [false, true]) {
    final withGuard = hasAppGuard ? ', with a guard of the app' : '';
    testWidgets('After back closed the tabs page, the second forward press '
        'shows Z1 on its entry, and the browser keeps its entries$withGuard', (
      tester,
    ) async {
      final app = _App(tester, hasAppGuard: hasAppGuard);
      await app.openZ1();
      expect(app.shown, 'Z1Route /tabs/one/z');
      // The entries the browser holds on Z1: before the walk, after it, and
      // after back and forward again.
      final heldOnZ1 = [app.browser.held];
      final asked = app.browser.asked.length;

      expect(await app.walk(app.browser.didPressBack, 3), [
        'TwoIndexRoute /tabs/two',
        'HomeRoute /',
      ]);
      expect(await app.walk(app.browser.didPressForward, 3), [
        'TwoIndexRoute /tabs/two',
        'Z1Route /tabs/one/z',
      ]);
      heldOnZ1.add(app.browser.held);

      // The entries stay the walk's: back and forward again.
      expect(await app.walk(app.browser.didPressBack, 1), [
        'TwoIndexRoute /tabs/two',
      ]);
      expect(await app.walk(app.browser.didPressForward, 1), [
        'Z1Route /tabs/one/z',
      ]);
      heldOnZ1.add(app.browser.held);
      expect(heldOnZ1, [_onZ1, _onZ1, _onZ1]);
      expect(app.askedSince(asked), isEmpty);
    });
  }

  // Steps: the steps of the issue, then select tab Two. Walk back to Home
  // and forward until nothing is ahead.
  // Was: the second forward press wrote two entries over the entry ahead.
  // So the third press found nothing to go to.
  testWidgets('Forward walks every entry ahead to the last one', (
    tester,
  ) async {
    final app = _App(tester);
    await app.openZ1();
    await app.selectTab(1);
    // Read before the walk: the entries the browser holds on Two.
    final heldOnTwo = app.browser.held;
    final asked = app.browser.asked.length;

    expect(await app.walk(app.browser.didPressBack, 4), [
      'Z1Route /tabs/one/z',
      'TwoIndexRoute /tabs/two',
      'HomeRoute /',
    ]);
    expect(await app.walk(app.browser.didPressForward, 4), [
      'TwoIndexRoute /tabs/two',
      'Z1Route /tabs/one/z',
      'TwoIndexRoute /tabs/two',
    ]);
    const onTwo = '/ /tabs/two /tabs/one/z >/tabs/two';
    expect((heldOnTwo, app.browser.held), (onTwo, onTwo));
    expect(app.askedSince(asked), isEmpty);
  });

  // Steps: on Home, open Tabs on tab One, select tab Two, then tab One. Walk
  // back to Home and forward until nothing is ahead.
  // Was: the forward press onto the entry of Two moved the browser back an
  // entry and forward again. Two is a tab never built in the tabs page that
  // forward opened again. Its nested router, built off the screen, reported
  // the url of tab One.
  testWidgets('Forward onto the first page of a tab never built moves the '
      'browser nowhere', (tester) async {
    final app = _App(tester);
    await app.openTabs();
    await app.selectTab(1);
    await app.selectTab(0);
    // Read before the walk: the entries the browser holds on One.
    final heldOnOne = app.browser.held;
    final asked = app.browser.asked.length;

    expect(await app.walk(app.browser.didPressBack, 4), [
      'TwoIndexRoute /tabs/two',
      'OneIndexRoute /tabs/one',
      'HomeRoute /',
    ]);
    expect(await app.walk(app.browser.didPressForward, 4), [
      'OneIndexRoute /tabs/one',
      'TwoIndexRoute /tabs/two',
      'OneIndexRoute /tabs/one',
    ]);
    const onOne = '/ /tabs/one /tabs/two >/tabs/one';
    expect((heldOnOne, app.browser.held), (onOne, onOne));
    expect(app.askedSince(asked), isEmpty);
  });
}
