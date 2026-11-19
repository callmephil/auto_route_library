import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, the pages of a nested router leave the browser's way back
// with the page that holds the router, as a tabs page or a shell, when the
// app closes that page (callmephil/auto_route_library#40).
//
// Steps: with includePrefixMatches, open the app at /tabs/two. The link
// opens Home under the tabs page, and the two share the link's entry. Push
// Detail, remove the tabs page with removeWhere, then press the browser's
// back button. The same cause shows in other steps too: pop the tabs page
// or a shell that the app pushed over Home, or remove a tabs page whose
// tabs have entries of their own.
// Was: the history took the pages of the closed page's nested router for
// open pages. A router keeps the nested router of a page that left among
// its children until the page's widget is gone, and the history looked
// there too. After the removal the browser still held the entry of tab
// Two under the entry of Detail, and back opened the tabs page again over
// Detail. A pop wrote the url of Home as a new entry after the entry of
// the closed page, and back opened the closed page again.
// Should: Home takes the link's entry over, and back from Detail shows
// Home. A pop steps the browser back to the entry of Home, as the pop of a
// page with no nested router does. A removal drops the entries of the
// tabs, and back from Detail shows Home.
//
// Native behavior this holds to: Flutter's Navigator, where pop and
// removeRoute take the route out with the navigator nested in it, and the
// system back then shows the route under it. The HTML standard's session
// history can't drop an entry, so the page under takes the entry of the
// closed page, or the browser steps back to the entry of that page.
//
// The same steps run in a real browser in
// test/web/back_after_closing_nested_router_page_web_test.dart, and in the
// example app in
// example.old/integration_test/back_after_closing_nested_router_page_test.dart.

// The routes of fork issue 20 with no guard: Home at '/', the tabs page at
// '/tabs' with the tabs One and Two, and Detail, for the push. And a shell
// with a nested router, for a pop.
class _Router extends RootStackRouter {
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

  NamedRouteDef _page(String name, String path) => .new(
    name: name,
    path: path,
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  @override
  late final List<AutoRoute> routes = [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [NamedRoute('OneRoute'), NamedRoute('TwoRoute')],
        builder: (_, child) => child,
      ),
      children: [_page('OneRoute', 'one'), _page('TwoRoute', 'two')],
    ),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell',
      builder: (_, _) => const AutoRouter(),
      children: [_page('XRoute', ''), _page('YRoute', 'y')],
    ),
    _page('DetailRoute', '/detail'),
  ];
}

// The app of a test, opened at [link] as a browser opens it, or at '/'.
class _App {
  new(this.tester, {String? link}) {
    if (link != null) {
      browser.entries
        ..clear()
        ..add((link, null));
      final dispatcher = tester.binding.platformDispatcher
        ..defaultRouteNameTestValue = link;
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    }
    router = _Router(browser);
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _Router router;

  // The page on top, the url the browser shows and the pages of the root's
  // stack.
  String get shown {
    final stack = router.stack.map((page) => page.routeData.name).join(' ');
    return '${router.topRoute.name} ${browser.url} [$stack]';
  }

  Future<void> open() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: true),
    );
    await browser.settle(tester);
  }

  // Runs [step] on the router, then lets the browser land.
  Future<void> run(void Function(_Router router) step) async {
    step(router);
    await browser.settle(tester);
  }

  // The page shown after each press of the browser's back button, until it
  // has no entry to go to, at most 4 presses.
  Future<List<String>> walkBack() async {
    final shownAfter = <String>[];
    for (var i = 0; i < 4 && browser.didPressBack(); i++) {
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }
}

void _push(_Router router, String name) =>
    unawaited(router.push<Object?>(NamedRoute(name)));

void _removeTabsPage(_Router router) =>
    router.removeWhere((route) => route.name == 'TabsRoute');

void main() {
  testWidgets('Opened at /tabs/two, push Detail, remove the tabs page: Home '
      "takes the link's entry, and back shows Home", (tester) async {
    final app = _App(tester, link: '/tabs/two');
    await app.open();
    await app.run((router) => _push(router, 'DetailRoute'));
    expect(app.browser.held, '/tabs/two >/detail');

    await app.run(_removeTabsPage);

    expect(
      (app.shown, app.browser.held),
      ('DetailRoute /detail [HomeRoute DetailRoute]', '/ >/detail'),
    );
    expect(await app.walkBack(), ['HomeRoute / [HomeRoute]']);
    expect(app.browser.held, '>/ /detail');
  });

  for (final (name, url) in [
    ('TabsRoute', '/tabs/one'),
    ('ShellRoute', '/shell'),
  ]) {
    testWidgets('Push $name over Home, then pop it: the browser steps back '
        'to the entry of Home', (tester) async {
      final app = _App(tester);
      await app.open();
      await app.run((router) => _push(router, name));
      expect(app.browser.held, '/ >$url');
      final asked = app.browser.asked.length;

      await app.run((router) => router.pop());

      expect(
        (app.shown, app.browser.held),
        ('HomeRoute / [HomeRoute]', '>/ $url'),
      );
      // A step back, and no new entry.
      expect(app.browser.asked.skip(asked), ['go -1']);
    });
  }

  testWidgets('Push the tabs page, pick tab Two, push Detail, remove the '
      'tabs page: back from Detail shows Home', (tester) async {
    final app = _App(tester);
    await app.open();
    await app.run((router) => _push(router, 'TabsRoute'));
    await app.run(
      (router) =>
          router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1),
    );
    await app.run((router) => _push(router, 'DetailRoute'));
    expect(app.browser.held, '/ /tabs/one /tabs/two >/detail');

    await app.run(_removeTabsPage);

    expect(
      (app.shown, app.browser.held),
      ('DetailRoute /detail [HomeRoute DetailRoute]', '/ >/detail'),
    );
    expect(await app.walkBack(), ['HomeRoute / [HomeRoute]']);
  });
}
