import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_sequences.dart';
import 'history_test_browser.dart';
import 'router_test_utils.dart';
import 'universal_link_test.dart' show didSendPlatformLink;

// The launch page rule ends at the first route that the Router hands over,
// also at a route that opens no page. A later link then opens over the page
// on screen (callmephil/auto_route_library#46).
//
// Steps: with includePrefixMatches: false, the app opens at / and shows Home.
// Off the web, the platform hands the app the link /nope, which no route
// matches, then the link /b, while the app stays on screen. In a VM test of
// the web history, with the test browser: on Home, push A, then B. Press the
// browser's back button two times, then its forward button, then its back
// button.
// Was: the rule, which lets the link of a cold start take the place of the
// launch page, stayed on after /nope and after the back presses, since they
// open no link. So /b took the place of Home: the stack held B alone, and the
// system back left the app. In the walk, the forward press showed A alone,
// and the back press then opened Home over A.
// Should: /b opens over Home, and the system back shows Home. The forward
// press shows A over Home, and the back press then shows Home alone. The
// first link after the launch still takes the place of the launch page.
//
// Native behavior this holds to: a link to an app that is open adds its page
// over the page on screen, as Flutter's Navigator.push does; only the link of
// a cold start has nothing under its page. In the HTML standard's session
// history, back and forward move through the entries in order and add or
// change none.
//
// A real browser never has the rule: it opens the app at its url, so the
// walk needs no test in Chrome. The links run in the example app in
// example.old/integration_test/link_after_route_without_page_test.dart.

// Home, A and B, among the pages of HistoryRouter. With [browser], the web
// history writes the test browser; without it, the app keeps its own history.
HistoryRouter _router({TestHistoryBrowser? browser}) {
  final router = HistoryRouter(
    isGuarded: false,
    history: (stack) => browser == null
        ? NavigationHistory.create(stack)
        : BrowserNavigationHistory(
            stack,
            browser,
            // The test's clock runs through every animation at once; the
            // browser of a test lands late, never too late.
            landingLimit: const Duration(hours: 1),
          ),
  );
  // The router disposes the history it made itself, not this one.
  addTearDown(router.navigationHistory.dispose);
  return router;
}

// Opens the app at / with prefix matches off, as on the web by default. No
// change of the app lifecycle ends the launch page rule here.
Future<void> _open(WidgetTester tester, HistoryRouter router) =>
    pumpRouterConfigApp(tester, router.config(includePrefixMatches: false));

String _stack(StackRouter router) =>
    router.stack.map((page) => page.name).join(' ');

void main() {
  // The link of a cold start, which iOS hands over after the first frame.
  testWidgets(
    'Off the web, the first link after the launch takes the place of the '
    'launch page',
    (tester) async {
      final router = _router();
      await _open(tester, router);

      await didSendPlatformLink(tester, '/b');
      expect(_stack(router), 'BRoute');
    },
    // A browser opens the app at its url, so the rule is never on there.
    skip: kIsWeb,
  );

  testWidgets(
    'Off the web, a link after a link that no route matches opens over Home, '
    'and the system back then shows Home',
    (tester) async {
      final router = _router();
      await _open(tester, router);

      await didSendPlatformLink(tester, '/nope');
      expect(_stack(router), 'HomeRoute');
      await didSendPlatformLink(tester, '/b');
      expect(_stack(router), 'HomeRoute BRoute');

      final isBackHandled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect((isBackHandled, _stack(router)), (true, 'HomeRoute'));
    },
    skip: kIsWeb,
  );

  testWidgets('With the web history, forward after two back presses shows A '
      'over Home, and back then shows Home alone', (tester) async {
    final browser = TestHistoryBrowser()..reportLandingsTo(tester);
    final router = _router(browser: browser);
    await _open(tester, router);
    await browser.settle(tester);
    for (final name in ['ARoute', 'BRoute']) {
      unawaited(router.push(NamedRoute<Object?>(name)));
      await browser.settle(tester);
    }
    final asked = browser.asked.length;

    final walk = <String>[];
    for (final press in [
      browser.didPressBack,
      browser.didPressBack,
      browser.didPressForward,
      browser.didPressBack,
    ]) {
      expect(press(), isTrue);
      await browser.settle(tester);
      walk.add('${_stack(router)} ${browser.url}');
    }

    expect(walk, [
      'HomeRoute ARoute /a',
      'HomeRoute /',
      'HomeRoute ARoute /a',
      'HomeRoute /',
    ]);
    // Back and forward wrote no entry and moved the browser nowhere.
    expect(browser.held, '>/ /a /b');
    expect(browser.asked.skip(asked), isEmpty);
  });
}
