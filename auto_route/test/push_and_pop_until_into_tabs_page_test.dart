import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, pushAndPopUntil into a tabs page that shows another tab
// leaves no entry of the old tab ahead of the browser
// (callmephil/auto_route_library#47).
//
// Steps: on Home, push Tabs on tab One and select tab Two. Call
// pushAndPopUntil of Tabs on tab One until Home. Press the browser's
// forward button, then its back button.
// Was: the app stepped the browser back two entries to Home, then one
// entry forward onto the old entry of tab One. The entry of tab Two stayed
// ahead, and the forward button showed tab Two again. The new tabs page
// takes over the screen of the old one, and the history writer took the
// old entry ahead for the entry of the new tab One, since it has the same
// url. The same in a plain stack when the new page has the url of a page
// that the call removed, also with popUntil and a push a frame later, and
// for a tab change of the app onto the entry ahead after back presses.
// Should: the browser steps back to Home and pushes /tabs/one, which drops
// the entries ahead. Forward finds no entry, and back shows Home. A back
// press that the page on top refuses still steps the browser forward onto
// the entry of that page.
//
// Native behavior this holds to: Flutter's Navigator.pushAndRemoveUntil,
// where the removed routes do not come back. In the HTML standard,
// history.pushState adds the entry of a navigation and drops the entries
// ahead, and only back and forward keep them.
//
// The same steps run in a real browser in
// test/web/push_and_pop_until_into_tabs_page_web_test.dart, and in the
// example app in
// example.old/integration_test/push_and_pop_until_into_tabs_page_test.dart.

// Home, the tabs page of the issue with the tabs One and Two, A, B, and
// Form, whose PopScope refuses every pop. Without a [_browser], the
// history is the app's own one off the web.
class _Router extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser? _browser;

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

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

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
    _page('ARoute', '/a'),
    _page('BRoute', '/b'),
    NamedRouteDef(
      name: 'FormRoute',
      path: '/form',
      builder: (_, _) =>
          const PopScope(canPop: false, child: Text('FormRoute')),
    ),
  ];
}

class _App {
  new(this.tester, {bool writesBrowser = true}) {
    router = _Router(writesBrowser ? browser : null);
    if (writesBrowser) {
      addTearDown(router.navigationHistory.dispose);
      browser.reportLandingsTo(tester);
    }
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
    await pumpRouterConfigApp(tester, router.config());
    await browser.settle(tester);
  }

  Future<void> run(void Function(_Router router) step) async {
    step(router);
    await browser.settle(tester);
  }

  Future<void> pressBack() async {
    expect(browser.didPressBack(), isTrue);
    await browser.settle(tester);
  }
}

bool _isHome(Route<Object?> route) => route.settings.name == 'HomeRoute';

void _push(_Router router, String name) =>
    unawaited(router.push(NamedRoute(name)));

TabsRouter _tabs(_Router router) => router.innerRouterOf('TabsRoute')!;

// The call of the issue, which takes every page over Home off.
void _pushTabsOnOneUntilHome(_Router router) => unawaited(
  router.pushAndPopUntil(
    const NamedRoute('TabsRoute', children: [NamedRoute('OneRoute')]),
    predicate: _isHome,
  ),
);

void main() {
  testWidgets('pushAndPopUntil of Tabs on tab One until Home, from tab Two: '
      'the browser steps back to Home and pushes /tabs/one, with no entry '
      'ahead', (tester) async {
    final app = _App(tester);
    await app.open();
    await app.run((router) => _push(router, 'TabsRoute'));
    await app.run((router) => _tabs(router).setActiveIndex(1));
    expect(app.browser.held, '/ /tabs/one >/tabs/two');
    final asked = app.browser.asked.length;

    await app.run(_pushTabsOnOneUntilHome);

    expect(
      (app.shown, app.browser.held),
      ('OneRoute /tabs/one [HomeRoute TabsRoute]', '/ >/tabs/one'),
    );
    expect(app.browser.asked.skip(asked), ['go -2', 'push /tabs/one']);
    expect(app.browser.didPressForward(), isFalse);
    await app.pressBack();
    expect(app.shown, 'HomeRoute / [HomeRoute]');
  });

  for (final (label, steps) in [
    (
      'pushAndPopUntil of A until Home',
      [
        (_Router router) => unawaited(
          router.pushAndPopUntil(
            const NamedRoute('ARoute'),
            predicate: _isHome,
          ),
        ),
      ],
    ),
    (
      'popUntil Home, then push A a frame later',
      [
        (_Router router) => router.popUntil(_isHome),
        (_Router router) => _push(router, 'ARoute'),
      ],
    ),
  ]) {
    testWidgets('On A and B over Home, $label: the browser steps back to '
        'Home and pushes /a, with no entry ahead', (tester) async {
      final app = _App(tester);
      await app.open();
      await app.run((router) => _push(router, 'ARoute'));
      await app.run((router) => _push(router, 'BRoute'));
      final asked = app.browser.asked.length;

      for (final step in steps) {
        await app.run(step);
      }

      expect(
        (app.shown, app.browser.held),
        ('ARoute /a [HomeRoute ARoute]', '/ >/a'),
      );
      expect(app.browser.asked.skip(asked), ['go -2', 'push /a']);
      expect(app.browser.didPressForward(), isFalse);
    });
  }

  // Steps: on Home, push Tabs, select tab Two and push A. Press back two
  // times, onto tab One, then select tab Two.
  testWidgets('A tab change after back presses pushes the tab, with no entry '
      'of the page that back closed ahead', (tester) async {
    final app = _App(tester);
    await app.open();
    await app.run((router) => _push(router, 'TabsRoute'));
    await app.run((router) => _tabs(router).setActiveIndex(1));
    await app.run((router) => _push(router, 'ARoute'));
    await app.pressBack();
    await app.pressBack();
    expect(app.browser.held, '/ >/tabs/one /tabs/two /a');
    final asked = app.browser.asked.length;

    await app.run((router) => _tabs(router).setActiveIndex(1));

    expect(
      (app.shown, app.browser.held),
      ('TwoRoute /tabs/two [HomeRoute TabsRoute]', '/ /tabs/one >/tabs/two'),
    );
    expect(app.browser.asked.skip(asked), ['push /tabs/two']);
  });

  // The control, right before the fix too: an entry ahead that is the app's
  // own, as the one a refused back press leaves, is still stepped onto.
  testWidgets('A back press that Form refuses steps the browser forward onto '
      'the entry of Form again', (tester) async {
    final app = _App(tester);
    await app.open();
    await app.run((router) => _push(router, 'FormRoute'));
    final asked = app.browser.asked.length;

    await app.pressBack();

    expect(
      (app.shown, app.browser.held),
      ('FormRoute /form [HomeRoute FormRoute]', '/ >/form'),
    );
    expect(app.browser.asked.skip(asked), ['go 1']);
  });

  // The control off the web, right before the fix too: the app's own
  // history holds Home and the new tab One.
  testWidgets('Off the web, back() after pushAndPopUntil of Tabs on tab One '
      'until Home shows Home', (tester) async {
    final app = _App(tester, writesBrowser: false);
    await app.open();
    await app.run((router) => _push(router, 'TabsRoute'));
    await app.run((router) => _tabs(router).setActiveIndex(1));
    await app.run(_pushTabsOnOneUntilHome);
    final history = app.router.navigationHistory;
    expect((history.length, app.router.currentUrl), (2, '/tabs/one'));

    app.router.back();
    await tester.pumpAndSettle();

    expect(
      (app.router.topRoute.name, history.canNavigateBack),
      ('HomeRoute', false),
    );
  }, skip: kIsWeb);
}
