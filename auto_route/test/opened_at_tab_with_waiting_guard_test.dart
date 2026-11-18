import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, an app opened at a link to a tab whose guard waits keeps the
// one browser entry the browser made for the link, with prefix matches too
// (callmephil/auto_route_library#20).
//
// Steps: with includePrefixMatches, open the app at /tabs/two. The link
// opens Home under the tabs page, and the guard of tab Two waits, so the
// tabs show tab One meanwhile. Then the guard says yes, or no in its place.
// Push Detail, then press the browser's back button and its forward button.
// Was: while the guard decided, the browser held two entries, the url of
// Home and then the url of tab One, and stood on the second. The tabs report
// the url of tab One in place of the link's url, and that report did not
// count as the link's, so Home got an entry of its own under it. After the
// yes, back from tab Two showed Home. After the no, which takes the tabs
// page back, both entries held the url of Home, and back showed Home again.
// Should: the link has one entry. It holds the url of tab One while the
// guard decides, then the url of tab Two after the yes, or the url of Home
// after the no. Home shares that entry. The push adds one entry, and back
// and forward walk between the two. A link to the tabs page that names no
// tab keeps one entry too: the tabs show tab One in its place, and the same
// report made the same second entry.
//
// Native behavior this holds to: the HTML standard's session history,
// where the browser makes one entry for a url it opens, and a back or
// forward traversal moves to another entry and adds or changes none.
// Flutter's Router reports its first route over the entry the app was
// opened at.
//
// The same steps run in a real browser in
// test/web/opened_at_tab_with_waiting_guard_web_test.dart, and in the
// example app in
// example.old/integration_test/opened_at_tab_with_waiting_guard_test.dart.

// A guard that answers only when the test tells it to, as in the report.
class _SlowGuard extends AutoRouteGuard {
  final pending = <NavigationResolver>[];

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) =>
      pending.add(resolver);
}

// The routes of the report: Home at '/', and the tabs page at '/tabs' with
// the tabs One and Two, whose guard is [guard]. And Detail, for the push.
class _LinkRouter extends RootStackRouter {
  new(this._browser, this.guard);

  final TestHistoryBrowser _browser;
  final _SlowGuard guard;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    // The test's clock runs through every animation at once; the browser
    // of a test lands late, never too late.
    landingLimit: const Duration(hours: 1),
  );

  NamedRouteDef _page(String name, String path, {AutoRouteGuard? tabGuard}) =>
      .new(
        name: name,
        path: path,
        guards: [?tabGuard],
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
      children: [
        _page('OneRoute', 'one'),
        _page('TwoRoute', 'two', tabGuard: guard),
      ],
    ),
    _page('DetailRoute', '/detail'),
  ];
}

// The app of a test, opened at [link] as a browser opens it.
class _App {
  new(this.tester, {required String link}) {
    browser.entries
      ..clear()
      ..add((link, null));
    final dispatcher = tester.binding.platformDispatcher
      ..defaultRouteNameTestValue = link;
    addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    router = _LinkRouter(browser, guard);
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  final guard = _SlowGuard();
  late final _LinkRouter router;

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // The pages of the root's stack.
  String get stack => router.stack.map((page) => page.routeData.name).join(' ');

  Future<void> open() async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: true),
    );
    await browser.settle(tester);
  }

  // Pushes Detail over the page on screen.
  Future<void> pushDetail() async {
    unawaited(router.push<Object?>(const NamedRoute('DetailRoute')));
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

  // Pushes Detail, then walks back to the link's entry and forward again:
  // the page shown after each press, and the entries after each walk.
  Future<List<Object>> pushDetailThenWalk() async {
    await pushDetail();
    // The elements are read in order, each after the walk before it.
    return [
      browser.held,
      await walk(browser.didPressBack, 4),
      browser.held,
      await walk(browser.didPressForward, 4),
      browser.held,
    ];
  }

  // What the app asked of the browser other than to write over the entry
  // it stands on: a new entry or a step.
  Iterable<String> get pushesAndSteps =>
      browser.asked.where((call) => !call.startsWith('replace '));
}

void main() {
  testWidgets('Opened at /tabs/two, the guard of tab Two says yes: one entry '
      'for the link, then a push and a walk between the two entries', (
    tester,
  ) async {
    final app = _App(tester, link: '/tabs/two');
    await app.open();
    // The guard, asked once, decides: tab One shows, over Home.
    expect(
      (app.shown, app.stack, app.browser.held, app.guard.pending.length),
      ('OneRoute /tabs/one', 'HomeRoute TabsRoute', '>/tabs/one', 1),
    );

    app.guard.pending.singleOrNull?.next();
    await app.browser.settle(tester);

    expect(
      (app.shown, app.stack, app.browser.held),
      ('TwoRoute /tabs/two', 'HomeRoute TabsRoute', '>/tabs/two'),
    );
    expect(app.pushesAndSteps, isEmpty);
    expect(await app.pushDetailThenWalk(), [
      '/tabs/two >/detail',
      ['TwoRoute /tabs/two'],
      '>/tabs/two /detail',
      ['DetailRoute /detail'],
      '/tabs/two >/detail',
    ]);
    // Back and forward added no entry and moved the browser nowhere.
    expect(app.pushesAndSteps, ['push /detail']);
  });

  testWidgets('Opened at /tabs/two, the guard of tab Two says no: one entry '
      'for the link, which shows Home', (tester) async {
    final app = _App(tester, link: '/tabs/two');
    await app.open();
    expect((app.browser.held, app.guard.pending.length), ('>/tabs/one', 1));

    app.guard.pending.singleOrNull?.reject();
    await app.browser.settle(tester);

    // The no takes the tabs page back: Home, which the link opened under
    // it, is left, at '/'.
    expect(
      (app.shown, app.stack, app.browser.held),
      ('HomeRoute /', 'HomeRoute', '>/'),
    );
    expect(await app.pushDetailThenWalk(), [
      '/ >/detail',
      ['HomeRoute /'],
      '>/ /detail',
      ['DetailRoute /detail'],
      '/ >/detail',
    ]);
    expect(app.pushesAndSteps, ['push /detail']);
  });

  testWidgets('Opened at /tabs, which names no tab: one entry for the link, '
      'with tab One', (tester) async {
    final app = _App(tester, link: '/tabs');
    await app.open();

    expect(
      (app.shown, app.stack, app.browser.held),
      ('OneRoute /tabs/one', 'HomeRoute TabsRoute', '>/tabs/one'),
    );
    expect(await app.pushDetailThenWalk(), [
      '/tabs/one >/detail',
      ['OneRoute /tabs/one'],
      '>/tabs/one /detail',
      ['DetailRoute /detail'],
      '/tabs/one >/detail',
    ]);
    expect(app.pushesAndSteps, ['push /detail']);
  });
}
