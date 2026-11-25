import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a typed url that the tabs of a new tabs page turn down keeps
// the url of its entry (callmephil/auto_route_library#60).
//
// Steps: on Home, push A, then type /store/hidden, a child of Store that the
// tabs of Store do not list, with prefix matches off and on, and with
// rebuildStackOnDeepLink off and on. Then press the browser's forward button.
// Was: the app wrote /store/shop over the typed entry, then stepped the
// browser back to A's entry, so forward opened Store on Shop. With
// rebuildStackOnDeepLink, the app stepped back to Home's entry, wrote over it
// and pushed /a, which dropped the typed entry.
// Should: the browser steps back to A's entry and changes no entry, as after
// a root guard's no. Forward opens the url again, the tabs turn it down
// again, and the browser steps back to A's entry. The app opened at the url
// keeps Store, its only page, on Shop, and the url names Shop. Off the web,
// back() after such a link shows Home, also with rebuildStackOnDeepLink.
// A back onto Depot, a deferred tabs page that still loads with /depot/hidden,
// puts no page on, so nothing takes Depot back: its url names its first tab.
// That Depot stays is older: the wait of the back takes the place of the wait
// of the navigation that opened Depot (callmephil/auto_route_library#72).
//
// Native behavior this holds to: in the HTML standard's session history, a
// traversal changes no entry; UITabBarController selects only a view
// controller of its viewControllers array; on Android,
// NavController.handleDeepLink returns false for a link it cannot open, and
// the back stack stays.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

List<AutoRoute> _routes(Future<void> depotLibrary) => [
  _page('Home', '/'),
  _page('A', '/a'),
  _page('C', '/c'),
  NamedRouteDef(
    name: 'Depot',
    path: '/depot',
    builder: (_, _) => DeferredWidget(
      () => depotLibrary,
      () => const AutoTabsRouter(
        routes: [NamedRoute<Object?>('DShop'), NamedRoute<Object?>('DAccount')],
      ),
      placeholder: const Text('Loading'),
    ),
    children: [
      _page('DShop', 'shop'),
      _page('DAccount', 'account'),
      _page('DHidden', 'hidden'),
    ],
  ),
  NamedRouteDef(
    name: 'Store',
    path: '/store',
    builder: (_, _) => const AutoTabsRouter(
      routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Account')],
    ),
    children: [
      _page('Shop', 'shop'),
      _page('Account', 'account'),
      _page('Hidden', 'hidden'),
    ],
  ),
];

class _Router extends RootStackRouter {
  new(this._browser, this._depotLibrary);

  final TestHistoryBrowser _browser;
  final Future<void> _depotLibrary;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    landingLimit: const Duration(hours: 1),
  );

  @override
  late final List<AutoRoute> routes = _routes(_depotLibrary);
}

class _App {
  new(this.tester) {
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  final depotLibrary = Completer<void>();
  late final router = _Router(browser, depotLibrary.future);

  // The page on top, the pages of the stack and the browser's entries.
  String get shown =>
      '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] ${browser.held}';

  Future<void> start({
    bool includePrefixMatches = false,
    bool rebuildStackOnDeepLink = false,
  }) async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(
        includePrefixMatches: includePrefixMatches,
        rebuildStackOnDeepLink: rebuildStackOnDeepLink,
      ),
    );
    await browser.settle(tester);
  }

  // The browser drops the entries ahead, makes an entry for [url] and lands
  // on it.
  Future<void> typeUrl(String url) async {
    browser.entries
      ..removeRange(browser.index + 1, browser.entries.length)
      ..add((url, null));
    browser.didPressForward();
    await browser.settle(tester);
  }
}

void main() {
  for (final (includePrefixMatches, rebuildStackOnDeepLink) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets('A typed url the tabs turn down keeps its url, and forward '
        'onto it shows A again, prefix matches $includePrefixMatches, '
        'rebuildStackOnDeepLink $rebuildStackOnDeepLink', (tester) async {
      final app = _App(tester);
      await app.start(
        includePrefixMatches: includePrefixMatches,
        rebuildStackOnDeepLink: rebuildStackOnDeepLink,
      );
      unawaited(app.router.push(const NamedRoute('A')));
      await app.browser.settle(tester);
      final asked = app.browser.asked.length;
      String reading() =>
          '${app.shown}, asked ${app.browser.asked.skip(asked).join(', ')}';

      await app.typeUrl('/store/hidden');
      final afterLink = reading();
      app.browser.didPressForward();
      await app.browser.settle(tester);

      expect(
        [afterLink, reading()],
        [
          'A [Home A] / >/a /store/hidden, asked go -1',
          'A [Home A] / >/a /store/hidden, asked go -1, go -1',
        ],
      );
    });
  }

  testWidgets('The app opened at a url its tabs turn down shows the first '
      'tab, and the url names it', (tester) async {
    final app = _App(tester);
    app.browser.entries
      ..clear()
      ..add(('/store/hidden', null));
    final dispatcher = tester.binding.platformDispatcher
      ..defaultRouteNameTestValue = '/store/hidden';
    addTearDown(dispatcher.clearDefaultRouteNameTestValue);

    await app.start();

    expect(app.shown, 'Shop [Store] >/store/shop');
  });

  for (final rebuildStackOnDeepLink in [false, true]) {
    testWidgets(
      'Off the web, back() after a link the tabs turn down shows Home, '
      'rebuildStackOnDeepLink $rebuildStackOnDeepLink',
      (tester) async {
        final router = RootStackRouter.build(routes: _routes(Future.value()));
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: rebuildStackOnDeepLink,
            includePrefixMatches: false,
          ),
        );
        unawaited(router.push(const NamedRoute('A')));
        await tester.pumpAndSettle();
        final history = router.navigationHistory;
        String reading() =>
            '${router.topRoute.name} '
            '[${router.stack.map((page) => page.name).join(' ')}] '
            '${router.urlState.url}, ${history.length} entries';

        await tester.binding.handlePushRoute('/store/hidden');
        await tester.pumpAndSettle();
        final afterLink = reading();
        router.back();
        await tester.pumpAndSettle();

        expect(
          [afterLink, reading()],
          ['A [Home A] /a, 2 entries', 'Home [Home] /, 1 entries'],
        );
      },
      skip: kIsWeb,
    );
  }

  for (final isTyped in [false, true]) {
    testWidgets('Back onto a loading tabs page whose tabs turn its url down '
        'names the first tab, and forward changes no entry, typed '
        '$isTyped', (tester) async {
      final app = _App(tester);
      await app.start();
      unawaited(app.router.push(const NamedRoute('A')));
      await app.browser.settle(tester);
      // What the app's own call hears: Depot stays, so nothing yet.
      final answers = <String>[];
      if (isTyped) {
        await app.typeUrl('/depot/hidden');
      } else {
        unawaited(
          app.router
              .navigatePath('/depot/hidden')
              .then<void>(
                (_) => answers.add('answered'),
                onError: (Object error) => answers.add('$error'),
              ),
        );
        await app.browser.settle(tester);
      }
      unawaited(app.router.push(const NamedRoute('C')));
      await app.browser.settle(tester);
      app.browser.didPressBack();
      await app.browser.settle(tester);
      app.depotLibrary.complete();
      await app.browser.settle(tester);
      final loaded = app.shown;
      final asked = app.browser.asked.length;
      app.browser.didPressForward();
      await app.browser.settle(tester);
      final forward =
          '${app.shown}, asked ${app.browser.asked.skip(asked).join(', ')}';
      app.browser.didPressBack();
      await app.browser.settle(tester);

      expect(
        [loaded, forward, app.shown, answers.join(', ')],
        [
          'DShop [Home A Depot] / /a >/depot/shop /c',
          'C [Home A Depot C] / /a /depot/shop >/c, asked ',
          'DShop [Home A Depot] / /a >/depot/shop /c',
          '',
        ],
      );
    });
  }

  testWidgets(
    'Off the web, back() onto a loading tabs page whose tabs turn its url '
    'down names the first tab',
    (tester) async {
      final depotLibrary = Completer<void>();
      final router = RootStackRouter.build(
        routes: _routes(depotLibrary.future),
      );
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: false),
      );
      unawaited(router.push(const NamedRoute('A')));
      await tester.pumpAndSettle();
      // What the app's own call hears: Depot stays, so nothing yet.
      final answers = <String>[];
      unawaited(
        router
            .navigatePath('/depot/hidden')
            .then<void>(
              (_) => answers.add('answered'),
              onError: (Object error) => answers.add('$error'),
            ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('C')));
      await tester.pumpAndSettle();
      router.back();
      await tester.pumpAndSettle();
      depotLibrary.complete();
      await tester.pumpAndSettle();

      expect(
        (
          '${router.topRoute.name} '
              '[${router.stack.map((page) => page.name).join(' ')}] '
              '${router.urlState.url}',
          answers.join(', '),
        ),
        ('DShop [Home A Depot] /depot/shop', ''),
      );
    },
    skip: kIsWeb,
  );
}
