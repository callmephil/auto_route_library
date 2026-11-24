import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, after the app closes pages in a tab not on screen, each press
// of the browser's back button shows another page
// (callmephil/auto_route_library#39).
//
// Steps: on Home, open Tabs on tab One; select tab Two; call
// pushAll([X1, Y1]) on the router of tab One; select tab One, which shows
// Y1, then tab Two again. Call removeUntil on the router of tab One, which
// is not on screen, until OneIndex. Press the browser's back button until
// Home, then its forward button until Two.
// Was: the first back press showed Two again, with no change on screen.
// The browser held an entry for Home, then OneIndex, then two for Two. The
// entries of X1 and Y1 left, and that put the two entries of Two side by
// side, and nothing made them one. The same with removeWhere and with
// popUntil in that router.
// Should: the browser holds the entries of Home, OneIndex and Two, with no
// entry ahead, so back shows OneIndex, then Home, and forward walks the
// same entries up to Two. X1 and Y1 lose their entries, as a page that the
// app takes off a tab not on screen does in
// test/back_after_push_all_in_hidden_tab_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where back closes the
// page on top and a removed page never comes back. The fork's history off
// the web keeps one entry for Two in the same steps, as the last test
// shows. In the HTML standard's session history, back and forward move to
// another entry and add or change none.
//
// The same walk runs in a real browser in
// test/web/back_after_remove_until_in_hidden_tab_web_test.dart, and in the
// example app in
// example.old/integration_test/back_after_remove_until_in_hidden_tab_test.dart.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Tabs with the tabs One and Two, each with a nested router: One
// with OneIndex, X1 and Y1, Two with TwoIndex.
final List<AutoRoute> _routes = [
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

// The router of the app: on the web with [_browser], off the web with the
// app's own history when it is null.
class _TabsRouter extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser? _browser;

  @override
  late final NavigationHistory navigationHistory = switch (_browser) {
    final testBrowser? => BrowserNavigationHistory(
      this,
      testBrowser,
      // The test's clock runs through every animation at once; the browser
      // of a test lands late, never too late.
      landingLimit: const Duration(hours: 1),
    ),
    null => super.navigationHistory,
  };

  @override
  List<AutoRoute> get routes => _routes;
}

// The ways the app closes X1 and Y1 in the router of tab One.
final Map<String, void Function(StackRouter one)> _closings = {
  'removeUntil': (one) =>
      one.removeUntil((route) => route.name == 'OneIndexRoute'),
  'removeWhere': (one) =>
      one.removeWhere((route) => route.name != 'OneIndexRoute'),
  'popUntil': (one) =>
      one.popUntil((route) => route.settings.name == 'OneIndexRoute'),
};

// The app of a test, on the web with [browser] unless [isOnWeb] is false.
class _App {
  new(this.tester, {bool isOnWeb = true})
    : browser = isOnWeb ? TestHistoryBrowser() : null {
    browser?.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final TestHistoryBrowser? browser;
  late final router = _TabsRouter(browser);

  TabsRouter get _tabs => router.innerRouterOf('TabsRoute')!;

  // The router of tab One.
  StackRouter get one => _tabs.innerRouterOf('OneRoute')!;

  // Runs the frames, and on the web lands every step, until the app and
  // the browser are still.
  Future<void> settle() async {
    switch (browser) {
      case final testBrowser?:
        await testBrowser.settle(tester);
      case null:
        await tester.pumpAndSettle();
    }
  }

  // Makes [call], then waits until the browser holds what the app shows.
  Future<void> run(void Function() call) async {
    call();
    await settle();
  }

  // On Two after the steps of the issue up to the closing.
  Future<void> openTwoAfterY1() async {
    if (browser != null) addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, router.config());
    await settle();
    await run(
      () => unawaited(router.push(const NamedRoute<Object?>('TabsRoute'))),
    );
    await run(() => _tabs.setActiveIndex(1));
    await run(
      () => unawaited(
        one.pushAll(const [
          NamedRoute<Object?>('X1Route'),
          NamedRoute<Object?>('Y1Route'),
        ]),
      ),
    );
    await run(() => _tabs.setActiveIndex(0));
    await run(() => _tabs.setActiveIndex(1));
  }
}

void main() {
  for (final MapEntry(key: name, value: close) in _closings.entries) {
    testWidgets('After $name in a tab not on screen, back shows OneIndex, '
        'then Home, and forward walks back to Two', (tester) async {
      final app = _App(tester);
      final browser = app.browser!;
      await app.openTwoAfterY1();
      expect(
        browser.held,
        '/ /tabs/one /tabs/two /tabs/one/x /tabs/one/y >/tabs/two',
      );
      final asked = browser.asked.length;

      await app.run(() => close(app.one));
      // Read after the closing: the entries the browser holds on Two, and
      // what the app asked of the browser.
      final heldAfterClosing = browser.held;
      final askedAtClosing = browser.asked.skip(asked).toList();

      String shown() => '${app.router.topRoute.name} ${browser.url}';
      final backWalk = <String>[];
      for (var i = 0; i < 4 && browser.didPressBack(); i++) {
        await app.settle();
        backWalk.add(shown());
      }
      expect(backWalk, ['OneIndexRoute /tabs/one', 'HomeRoute /']);
      expect(browser.held, '>/ /tabs/one /tabs/two');

      final forwardWalk = <String>[];
      for (var i = 0; i < 4 && browser.didPressForward(); i++) {
        await app.settle();
        forwardWalk.add(shown());
      }
      expect(forwardWalk, [
        'OneIndexRoute /tabs/one',
        'TwoIndexRoute /tabs/two',
      ]);
      // The browser held one entry for Two and none ahead, after the
      // closing and after the walk. The closing stepped the browser back
      // over the entries of X1, Y1 and the first of Two, and wrote Two
      // again, which dropped the entries ahead.
      expect(askedAtClosing, ['go -4', 'push /tabs/two']);
      const onTwo = '/ /tabs/one >/tabs/two';
      expect((heldAfterClosing, browser.held), (onTwo, onTwo));
    });
  }

  // The native control, right before the fix too: off the web, the app's
  // own history keeps one entry for Two, and back() shows OneIndex, then
  // Home.
  testWidgets('Off the web, after removeUntil in a tab not on screen, back() '
      'shows OneIndex, then Home', (tester) async {
    final app = _App(tester, isOnWeb: false);
    await app.openTwoAfterY1();
    final history = app.router.navigationHistory;

    await app.run(() => _closings['removeUntil']!(app.one));

    expect(history.length, 3);
    final walk = <String>[];
    while (history.canNavigateBack) {
      history.back();
      await app.settle();
      walk.add('${app.router.topRoute.name} ${app.router.urlState.url}');
    }
    expect(walk, ['OneIndexRoute /tabs/one', 'HomeRoute /']);
  }, skip: kIsWeb);
}
