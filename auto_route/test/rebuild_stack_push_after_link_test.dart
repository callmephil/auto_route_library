import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// After a link replaces the stack, the app's next push adds one entry, and
// forward presses change no entry (callmephil/auto_route_library#51).
//
// Steps: router.config(rebuildStackOnDeepLink: true, includePrefixMatches:
// true). On Home, push A, type /b into the address bar, then push C. Off the
// web, the platform hands over /b, and back() follows the push.
// Was: the app wrote / over the entry of /b, then pushed /b and /c. Off the
// web, back() from C stayed on C.
// Should: the app pushes /c alone, and back() shows B.
//
// Or with the tabs page Store: with the flag, open Store on Orders, type
// /store/account and push A. Or, without it, reload on Account with A
// ahead. Then press back until Home and forward until A.
// Was: forward onto the entry of Account stepped the browser back and
// pushed /store/account, which removed the entry of A
// (callmephil/auto_route_library#54).
// Should: no press asks the browser for a step or a write.
//
// Native behavior this holds to: the HTML standard's session history, where
// history.pushState adds one entry after the current one and a back or
// forward traversal adds or changes none; Flutter's Navigator.push adds one
// route over the route on top.

class _Router extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser? _browser;

  @override
  late final NavigationHistory navigationHistory = switch (_browser) {
    final browser? => BrowserNavigationHistory(
      this,
      browser,
      landingLimit: const Duration(hours: 1),
    ),
    null => super.navigationHistory,
  };

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    _page('A', '/a'),
    _page('B', '/b'),
    _page('C', '/c'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('Shop'),
            NamedRoute<Object?>('Orders'),
            NamedRoute<Object?>('Account'),
          ],
        ),
      ),
      children: [
        _page('Shop', 'shop'),
        _page('Orders', 'orders'),
        _page('Account', 'account'),
      ],
    ),
  ];
}

class _App {
  new(this.tester, {bool writesBrowser = true})
    : _browser = writesBrowser ? TestHistoryBrowser() : null {
    _browser?.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final TestHistoryBrowser? _browser;
  TestHistoryBrowser get browser => _browser!;
  late final router = _Router(_browser);

  // The page on top, the pages of the stack and the browser's entries.
  String get shown =>
      '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] '
      '${_browser?.held ?? ''}';

  Future<void> start({
    required bool rebuildStack,
    bool includePrefixMatches = false,
  }) async {
    if (_browser != null) addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(
        rebuildStackOnDeepLink: rebuildStack,
        includePrefixMatches: includePrefixMatches,
      ),
    );
    await settle();
  }

  Future<void> settle() async {
    await tester.pumpAndSettle();
    await _browser?.settle(tester);
  }

  Future<void> push(String name) async {
    unawaited(router.push(NamedRoute<Object?>(name)));
    await settle();
  }

  // The browser drops the entries ahead, makes an entry for [url] and lands
  // on it.
  Future<void> typeUrl(String url) async {
    browser.entries
      ..removeRange(browser.index + 1, browser.entries.length)
      ..add((url, null));
    browser.didPressForward();
    await settle();
  }

  // What each of [presses] shows and asks of the browser, until one has no
  // entry.
  Future<List<String>> walk(List<bool Function()> presses) async {
    final shownAfter = <String>[];
    for (final press in presses) {
      final asked = browser.asked.length;
      if (!press()) break;
      await settle();
      shownAfter.add('$shown ${browser.asked.skip(asked).toList()}');
    }
    return shownAfter;
  }
}

void main() {
  testWidgets('A push after a typed url adds one entry after its entry', (
    tester,
  ) async {
    final app = _App(tester);
    await app.start(rebuildStack: true, includePrefixMatches: true);
    await app.push('A');
    await app.typeUrl('/b');
    final afterLink = app.shown;
    final isMarked = app.router.navigationHistory.isUrlStateMarkedForReplace;
    final asked = app.browser.asked.length;

    await app.push('C');

    expect(
      (app.shown, app.browser.asked.skip(asked).join(', ')),
      ('C [Home B C] / /a /b >/c', 'push /c'),
    );
    expect((afterLink, isMarked), ('B [Home B] / /a >/b', false));
  });

  testWidgets(
    'Off the web, back() after a push that follows a link shows the page of '
    'the link',
    (tester) async {
      final app = _App(tester, writesBrowser: false);
      await app.start(rebuildStack: true, includePrefixMatches: true);
      await app.push('A');
      await tester.binding.handlePushRoute('/b');
      await app.settle();
      await app.push('C');

      app.router.back();
      await app.settle();

      expect(app.router.topRoute.name, 'B');
    },
    skip: kIsWeb,
  );

  testWidgets('After a typed url to Account and a push of A, forward walks '
      'back to A and changes no entry', (tester) async {
    final app = _App(tester);
    await app.start(rebuildStack: true);
    unawaited(app.router.pushPath<Object?>('/store/orders'));
    await app.settle();
    await app.typeUrl('/store/account');
    await app.push('A');
    expect(app.shown, 'A [Store A] / /store/orders /store/account >/a');

    final back = app.browser.didPressBack;
    final forward = app.browser.didPressForward;
    expect(await app.walk([back, back, back, forward, forward, forward]), [
      'Account [Store] / /store/orders >/store/account /a []',
      'Orders [Store] / >/store/orders /store/account /a []',
      'Home [Home] >/ /store/orders /store/account /a []',
      'Orders [Home Store] / >/store/orders /store/account /a []',
      'Account [Home Store] / /store/orders >/store/account /a []',
      'A [Home Store A] / /store/orders /store/account >/a []',
    ]);
  });

  testWidgets('After a reload on Account with A ahead, forward walks to A '
      'and changes no entry', (tester) async {
    final app = _App(tester);
    app.browser.entries
      ..clear()
      ..addAll([
        ('/', null),
        ('/store/orders', null),
        ('/store/account', null),
        ('/a', null),
      ]);
    app.browser.index = 2;
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/store/account';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await app.start(rebuildStack: false);

    final back = app.browser.didPressBack;
    final forward = app.browser.didPressForward;
    expect(await app.walk([back, back, forward, forward, forward]), [
      'Orders [Store] / >/store/orders /store/account /a []',
      'Home [Home] >/ /store/orders /store/account /a []',
      'Orders [Home Store] / >/store/orders /store/account /a []',
      'Account [Home Store] / /store/orders >/store/account /a []',
      'A [Home Store A] / /store/orders /store/account >/a []',
    ]);
  });
}
