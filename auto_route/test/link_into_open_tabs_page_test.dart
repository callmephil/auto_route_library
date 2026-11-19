import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a link into another tab of the tabs page on screen gets one
// entry, and the app moves the browser nowhere
// (callmephil/auto_route_library#35).
//
// Steps: on Home, open Tabs on tab One, then select tab Two. Hand the app
// the link /tabs/one/z, as the platform hands one over, or type it into the
// address bar. Then press the browser's back button until Home, and its
// forward button until Z1.
// Was: the entries ended right, but the browser stepped back an entry and
// forward again. The link opens the tabs page again over the one on screen,
// which keeps its tabs. That page went on first, and its url report named
// the tab the tabs still showed, Two. The web history then dropped the
// link's entry, whose page Z1 was not open yet, and the browser stepped back
// to the entry of Two. The url of Z1 then stepped it forward again. For a
// typed url, the browser stepped back from the entry it made for the link,
// and the app wrote the link's url again as a new entry. The same with a
// tab One never built, with a guard of Z1 that waits, and with the
// AutoTabsRouter.builder tabs.
// Should: the platform's link adds one entry, which the browser stands on
// while the app opens its page, and a typed url keeps the entry the browser
// made for it. Back and forward walk Two, One and Home, and back again.
//
// Native behavior this holds to: the HTML standard's session history,
// where a navigation to a new url adds one entry, and the browser moves
// between entries only by a traversal the user or the page asks for. Off
// the web, a link adds one step back, as each call of Android's
// NavController.navigate pushes one destination.
//
// The same steps run in a real browser in
// test/web/link_into_open_tabs_page_web_test.dart, and in the example app in
// example.old/integration_test/link_into_open_tabs_page_test.dart.

// The app of the issue: Home, then Tabs with the tabs One and Two, each with
// a nested router: One with OneIndex and Z1, whose guard waits [z1Wait]
// when it is more than zero, Two with TwoIndex. With [isBuilder], the tabs
// page builds every tab at once, with AutoTabsRouter.builder. With a
// [_browser], the router writes it; without one, the history is the app's
// own one off the web.
class _TabsRouter extends RootStackRouter {
  new(this._browser, {required this.z1Wait, required this.isBuilder});

  final TestHistoryBrowser? _browser;
  final Duration z1Wait;
  final bool isBuilder;

  @override
  late final NavigationHistory navigationHistory = switch (_browser) {
    final browser? => BrowserNavigationHistory(
      this,
      browser,
      // The test's clock runs through every animation at once; the browser
      // of a test lands late, never too late.
      landingLimit: const Duration(hours: 1),
    ),
    null => super.navigationHistory,
  };

  static const _tabRoutes = [
    NamedRoute<Object?>('OneRoute'),
    NamedRoute<Object?>('TwoRoute'),
  ];

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => isBuilder
          ? AutoTabsRouter.builder(
              routes: _tabRoutes,
              builder: (_, children, tabs) =>
                  IndexedStack(index: tabs.activeIndex, children: children),
            )
          : AutoTabsRouter(routes: _tabRoutes, builder: (_, child) => child),
      children: [
        NamedRouteDef(
          name: 'OneRoute',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OneIndexRoute', ''),
            NamedRouteDef(
              name: 'Z1Route',
              path: 'z',
              guards: [
                // A check of the page's own that waits, as for its data.
                if (z1Wait > .zero)
                  AutoRouteGuard.simple((resolver, _) async {
                    await Future<void>.delayed(z1Wait);
                    resolver.next();
                  }),
              ],
              builder: (_, _) => const Text('Z1Route'),
            ),
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

// The app of a test and the browser it writes.
class _App {
  new(
    this.tester, {
    Duration z1Wait = .zero,
    bool isBuilder = false,
    bool writesBrowser = true,
  }) {
    router = _TabsRouter(
      writesBrowser ? browser : null,
      z1Wait: z1Wait,
      isBuilder: isBuilder,
    );
    if (writesBrowser) {
      addTearDown(router.navigationHistory.dispose);
      browser.reportLandingsTo(tester);
    }
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _TabsRouter router;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // Opens Tabs on tab One over Home, then selects tab Two.
  Future<void> openTwo() async {
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await browser.settle(tester);
    router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
    await browser.settle(tester);
  }

  // Opens Tabs at /tabs/two over Home: tab One is never built.
  Future<void> openAtTwo() async {
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
    unawaited(router.pushPath<Object?>('/tabs/two'));
    await browser.settle(tester);
  }

  // The platform hands the app the link /tabs/one/z.
  Future<void> handOverLink() async {
    await tester.binding.handlePushRoute('/tabs/one/z');
    await browser.settle(tester);
  }

  // The user types /tabs/one/z into the address bar: the browser makes an
  // entry for it after the one it stands on, which drops the entries
  // ahead, and lands there.
  Future<void> typeLink() async {
    browser.entries
      ..removeRange(browser.index + 1, browser.entries.length)
      ..add(('/tabs/one/z', null));
    browser.didPressForward();
    await browser.settle(tester);
  }

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
  for (final (label, z1Wait, isBuilder) in [
    ('', Duration.zero, false),
    (', with a guard of Z1 that waits', const Duration(milliseconds: 1), false),
    (', with the builder tabs', Duration.zero, true),
  ]) {
    testWidgets('The link /tabs/one/z from tab Two gets one entry and moves '
        'the browser nowhere$label', (tester) async {
      final app = _App(tester, z1Wait: z1Wait, isBuilder: isBuilder);
      await app.openTwo();
      final asked = app.browser.asked.length;

      await app.handOverLink();

      expect(app.shown, 'Z1Route /tabs/one/z');
      expect(app.browser.asked.skip(asked), ['push /tabs/one/z']);
      // Read before the walk: the entries the browser holds on Z1.
      final heldOnZ1 = app.browser.held;
      expect(await app.walk(app.browser.didPressBack, 4), [
        'TwoIndexRoute /tabs/two',
        'OneIndexRoute /tabs/one',
        'HomeRoute /',
      ]);
      expect(await app.walk(app.browser.didPressForward, 4), [
        'OneIndexRoute /tabs/one',
        'TwoIndexRoute /tabs/two',
        'Z1Route /tabs/one/z',
      ]);
      const onZ1 = '/ /tabs/one /tabs/two >/tabs/one/z';
      expect((heldOnZ1, app.browser.held), (onZ1, onZ1));
      expect(app.browser.asked.skip(asked + 1), isEmpty);
    });
  }

  // Steps: on Home, push the path /tabs/two, then hand over the link.
  testWidgets('The link /tabs/one/z into a tab never built gets one entry '
      'and moves the browser nowhere', (tester) async {
    final app = _App(tester);
    await app.openAtTwo();
    final asked = app.browser.asked.length;

    await app.handOverLink();

    expect(app.shown, 'Z1Route /tabs/one/z');
    expect(app.browser.asked.skip(asked), ['push /tabs/one/z']);
    expect(app.browser.held, '/ /tabs/two >/tabs/one/z');
  });

  testWidgets('The url /tabs/one/z typed on tab Two keeps the entry the '
      'browser made for it', (tester) async {
    final app = _App(tester);
    await app.openTwo();
    final asked = app.browser.asked.length;

    await app.typeLink();

    expect(app.shown, 'Z1Route /tabs/one/z');
    expect(app.browser.asked.skip(asked), isEmpty);
    expect(app.browser.held, '/ /tabs/one /tabs/two >/tabs/one/z');
  });

  // The control off the web, right before the fix too: the app's own
  // history gives the link one entry.
  testWidgets('Off the web, back() after the link /tabs/one/z from tab Two '
      'shows Two, One and Home', (tester) async {
    final app = _App(tester, writesBrowser: false);
    await app.openTwo();
    await app.handOverLink();
    expect(app.router.currentUrl, '/tabs/one/z');

    final shownAfter = <String>[];
    for (
      var i = 0;
      i < 4 && app.router.navigationHistory.canNavigateBack;
      i++
    ) {
      app.router.back();
      await tester.pumpAndSettle();
      shownAfter.add('${app.router.topRoute.name} ${app.router.currentUrl}');
    }
    expect(shownAfter, [
      'TwoIndexRoute /tabs/two',
      'OneIndexRoute /tabs/one',
      'HomeRoute /',
    ]);
  }, skip: kIsWeb);
}
