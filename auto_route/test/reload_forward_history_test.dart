import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_sequences.dart';
import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, after a reload on B over A over Home and two presses of the
// back button, the forward button still walks the entries ahead to B's.
//
// Before, the pages open when the app followed the browser onto an entry
// from before the reload were counted as sharing that entry, though their
// own entries are ahead. The first forward press closed Home, which handed
// its entry to B; the history wrote /b there and /a after it as a new
// entry, which dropped B's entry ahead, so no forward press reached B.
//
// The steps: the browser holds /, /a and /b and stands on /b, as a reload
// leaves it; the app starts on /b with B alone; back twice, forward three
// times, the third with nothing ahead. The back presses show A, then Home,
// each alone (test/web/reload_back_web_test.dart pins them in Chrome); this
// pins that the forward walk keeps its entries and ends on B.
//
// Native behavior this holds to: the HTML History API, where a reload
// keeps the tab's entries and the forward button walks the ones ahead; only
// history.pushState drops them, so a step the user makes is followed
// without a push.
void main() {
  testWidgets('After a reload on B: back, back, then forward reaches B', (
    tester,
  ) async {
    final browser = TestHistoryBrowser();
    browser.entries
      ..clear()
      ..addAll([('/', null), ('/a', null), ('/b', null)]);
    browser.index = 2;
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/b';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = HistoryRouter(
      isGuarded: false,
      history: (stack) => BrowserNavigationHistory(
        stack,
        browser,
        landingLimit: const Duration(hours: 1),
      ),
    );
    // The engine reports each entry the browser lands on to the Router.
    browser.reportLandingsTo(tester);
    addTearDown(router.navigationHistory.dispose);
    Future<void> settle() => browser.settle(tester);

    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );
    await settle();
    for (var i = 0; i < 2; i++) {
      browser.didPressBack();
      await settle();
    }
    final forwardWalk = <String>[];
    for (var i = 0; i < 3 && browser.didPressForward(); i++) {
      await settle();
      final stack = router.stack.map((page) => page.name).join(' ');
      forwardWalk.add('$stack ${browser.url}, ${browser.entries.length}');
    }
    expect(forwardWalk, [
      'HomeRoute ARoute /a, 3',
      'HomeRoute ARoute BRoute /b, 3',
    ]);
  });
}
