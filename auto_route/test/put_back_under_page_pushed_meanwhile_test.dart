import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// When the tabs of a page that a link or a replace put on are built late and
// turn its route down, the pages that the link or the replace took off come
// back in the place of that page, under a page that the app pushed meanwhile
// (callmephil/auto_route_library#58).
//
// Steps: on Home, push A. Open /depot/hidden: type it on the web, or get it
// from the platform off the web, both with rebuildStackOnDeepLink, or call
// replacePath, replace or replaceAll, on the web and off it. Depot builds
// its tabs once its library loads, and they do not list Hidden. Or
// replacePath /lazy/attic: a FutureBuilder builds the tabs of Lazy once a
// future completes. While the page waits, push C. Then let the tabs build,
// and press back two times.
// Was: C Home A, and A showed. Back then showed Home, then C. After replace
// and replacePath: Home C A, and back showed C, then Home. On the web, the
// browser held /c / /a, or / /c /a after replace and replacePath.
// Should: Home A C, and C stays on screen. Back shows A, then Home. On the
// web, the browser holds one entry for each page, / /a /c, and stands on the
// entry of C. A path state that A pushed before the typed url keeps its
// entry under C, as it does when no page went on. When C went on and closed
// before the tabs were built, the browser steps back to that entry of A.
// Was: to the entry of A before it.
//
// Native behavior this holds to: Flutter's Navigator.replace puts the new
// route at the index of the old route and keeps the routes above it, and
// Navigator.removeRoute keeps the order of the other routes. In the HTML
// standard's session history, history.pushState drops the entries ahead.

class _WebRouter extends RootStackRouter {
  new(this._browser, this.routes);

  final TestHistoryBrowser _browser;

  @override
  final List<AutoRoute> routes;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    landingLimit: const Duration(hours: 1),
  );
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// The tabs of Depot and Lazy are built once [gate] completes.
List<AutoRoute> _routes(Completer<void> gate) => [
  _page('Home', '/'),
  _page('A', '/a'),
  _page('C', '/c'),
  NamedRouteDef(
    name: 'Depot',
    path: '/depot',
    builder: (_, _) => DeferredWidget(
      () => gate.future,
      () => const AutoTabsRouter(
        routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Desk')],
      ),
      placeholder: const Text('Loading'),
    ),
    children: [
      _page('Shop', 'shop'),
      _page('Desk', 'desk'),
      _page('Hidden', 'hidden'),
    ],
  ),
  NamedRouteDef(
    name: 'Lazy',
    path: '/lazy',
    builder: (_, _) => FutureBuilder<void>(
      future: gate.future,
      builder: (_, snapshot) => snapshot.connectionState == .done
          ? const AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('Front'),
                NamedRoute<Object?>('Rear'),
              ],
            )
          : const Text('Loading'),
    ),
    children: [
      _page('Front', 'front'),
      _page('Rear', 'rear'),
      _page('Attic', 'attic'),
    ],
  ),
];

const _depotHidden = NamedRoute<Object?>(
  'Depot',
  children: [NamedRoute<Object?>('Hidden')],
);

enum _Opening { typedUrl, platformLink, replacePath, replace, replaceAll }

class _App {
  new(this.tester, {required this.isWeb}) {
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final bool isWeb;
  final browser = TestHistoryBrowser();
  final gate = Completer<void>();
  late final RootStackRouter router = isWeb
      ? _WebRouter(browser, _routes(gate))
      : .build(routes: _routes(gate));

  // The page on top, the pages of the stack, and the url, which on the web
  // is each entry of the browser.
  String get shown =>
      '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] '
      '${isWeb ? browser.held : router.urlState.url}';

  Future<void> openA({required bool rebuildsStack}) async {
    if (isWeb) addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(
        rebuildStackOnDeepLink: rebuildsStack,
        includePrefixMatches: false,
      ),
    );
    await browser.settle(tester);
    unawaited(router.push(const NamedRoute('A')));
    await browser.settle(tester);
  }

  // Opens [url] as [opening] does, pushes C while its page waits for its
  // tabs, and pops C again with [popsC], then lets the tabs build.
  Future<void> openAndPushC(
    _Opening opening,
    String url, {
    bool popsC = false,
  }) async {
    final failures = <NavigationFailure>[];
    switch (opening) {
      case .typedUrl:
        browser.entries
          ..removeRange(browser.index + 1, browser.entries.length)
          ..add((url, null));
        browser.didPressForward();
      case .platformLink:
        unawaited(tester.binding.handlePushRoute(url));
      case .replacePath:
        unawaited(router.replacePath(url, onFailure: failures.add));
      case .replace:
        unawaited(router.replace(_depotHidden, onFailure: failures.add));
      case .replaceAll:
        unawaited(router.replaceAll([_depotHidden], onFailure: failures.add));
    }
    await browser.settle(tester);
    unawaited(router.push(const NamedRoute('C')));
    await browser.settle(tester);
    if (popsC) {
      unawaited(router.maybePop());
      await browser.settle(tester);
    }
    gate.complete();
    await browser.settle(tester);
  }

  // What shows after each of [times] presses of the back button: the
  // browser's on the web, the system's off the web.
  Future<List<String>> pressBack(int times) async {
    final shownAfter = <String>[];
    for (var press = 0; press < times; press++) {
      if (isWeb) {
        browser.didPressBack();
      } else {
        await tester.binding.handlePopRoute();
      }
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }
}

void main() {
  for (final (opening, url, rebuildsStack) in [
    (_Opening.typedUrl, '/depot/hidden', true),
    (_Opening.platformLink, '/depot/hidden', true),
    (_Opening.replacePath, '/depot/hidden', false),
    (_Opening.replace, '/depot/hidden', false),
    (_Opening.replaceAll, '/depot/hidden', false),
    (_Opening.replacePath, '/lazy/attic', false),
    // Without the flag, the typed url pushes Depot over A, and the turn-down
    // takes Depot back: C stayed on top before the fix too.
    (_Opening.typedUrl, '/depot/hidden', false),
  ]) {
    // The app's own calls on the web and off it.
    for (final isWeb in [
      if (opening != .platformLink) true,
      if (opening != .typedUrl) false,
    ]) {
      testWidgets('C stays on top once ${opening.name} $url is turned down, '
          '${isWeb ? 'on' : 'off'} the web, '
          'rebuildStackOnDeepLink $rebuildsStack', (tester) async {
        final app = _App(tester, isWeb: isWeb);
        await app.openA(rebuildsStack: rebuildsStack);
        await app.openAndPushC(opening, url);
        final afterTurnDown = app.shown;
        final onScreen = find.text('C').evaluate().length;

        expect(
          [afterTurnDown, ...await app.pressBack(2)],
          isWeb
              ? [
                  'C [Home A C] / /a >/c',
                  'A [Home A] / >/a /c',
                  'Home [Home] >/ /a /c',
                ]
              : ['C [Home A C] /c', 'A [Home A] /a', 'Home [Home] /'],
        );
        expect(onScreen, 1);
      }, skip: !isWeb && kIsWeb);
    }
  }

  // The entries of the pages that come back, a path state included, are the
  // ones they had: also when C closed before the tabs were built.
  for (final (popsC, walk) in [
    (
      false,
      [
        'C [Home A C] / /a /a#picked >/c',
        'A [Home A] / /a >/a#picked /c',
        'A [Home A] / >/a /a#picked /c',
        'Home [Home] >/ /a /a#picked /c',
      ],
    ),
    (
      true,
      [
        'A [Home A] / /a >/a#picked /depot/hidden /c',
        'A [Home A] / >/a /a#picked /depot/hidden /c',
        'Home [Home] >/ /a /a#picked /depot/hidden /c',
      ],
    ),
  ]) {
    testWidgets('A path state that A pushed before the typed url keeps its '
        'entry when C ${popsC ? 'went on and closed' : 'went on'} while the '
        'tabs waited', (tester) async {
      final app = _App(tester, isWeb: true);
      await app.openA(rebuildsStack: true);
      app.router.navigationHistory.pushPathState('picked');
      await app.browser.settle(tester);
      await app.openAndPushC(.typedUrl, '/depot/hidden', popsC: popsC);
      final afterTurnDown = app.shown;

      expect([afterTurnDown, ...await app.pressBack(walk.length - 1)], walk);
    });
  }
}
