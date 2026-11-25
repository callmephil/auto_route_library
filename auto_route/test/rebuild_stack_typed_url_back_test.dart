import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, with rebuildStackOnDeepLink, the entries of the pages that a
// typed url closed show their page alone, and no press changes an entry
// (callmephil/auto_route_library#43).
//
// Steps: router.config(rebuildStackOnDeepLink: true). On Home, push A, type
// /b into the address bar, then press back twice and forward twice, with
// prefix matches off and on. Or push C after the typed url.
// Was: back showed A over B, moved the browser back one more entry and wrote
// /a over the entry of Home, and a second back found no entry. A push of C
// went back two entries and wrote /b over the entry of Home.
// Should: back shows A alone on its entry, then Home alone on its entry, and
// forward walks the same entries up to B, as after a reload. C gets a new
// entry after the typed url's.
//
// Or type /store/hidden, a route the tabs of Store do not list, so the tabs
// turn the link down and Home and A come back. Should: the browser steps
// back to A's entry and changes no entry, as after a root guard's no and as
// before the app's first entry moved to the link's entry
// (callmephil/auto_route_library#60). A guard of a tab or of a nested stack
// router that says no keeps the link's page instead, on the typed entry, and
// back shows A alone, then Home alone.
//
// Then open a dialog over A and press forward twice. Should: each forward
// opens the url again over A, the tabs turn it down again, and the browser
// steps back to A's entry, as for /closed, whose root guard says no; A and
// its dialog stay. Or type /depot/hidden, whose tabs page loads a library
// first, and push C meanwhile. Should: one entry for each page, / /a /c,
// with C over the pages put back (callmephil/auto_route_library#58). Push C
// and pop it instead, then jump two entries forward over the typed entry:
// the jump ends on A, as a forward onto that entry does.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal goes to another entry and adds or changes none, and
// history.pushState adds an entry after the current one; and Flutter's
// Navigator, where back from [Home, A] shows Home once.

class _Router extends RootStackRouter {
  new(this._browser);

  final TestHistoryBrowser _browser;
  final library = Completer<void>();

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    landingLimit: const Duration(hours: 1),
  );

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  NamedRouteDef _refused(String name, String path) => .new(
    name: name,
    path: path,
    guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
    builder: (_, _) => Text(name),
  );

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    _page('A', '/a'),
    _page('B', '/b'),
    _page('C', '/c'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const AutoTabsRouter(
        routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Account')],
      ),
      children: [
        _page('Shop', 'shop'),
        _refused('Account', 'account'),
        _page('Hidden', 'hidden'),
      ],
    ),
    // The test browser keeps a url under '/kept' out, as neglectWhen does.
    NamedRouteDef(
      name: 'KeptStore',
      path: '/keptstore',
      builder: (_, _) =>
          const AutoTabsRouter(routes: [NamedRoute<Object?>('KeptShop')]),
      children: [_page('KeptShop', 'shop'), _page('KeptHidden', 'hidden')],
    ),
    NamedRouteDef(
      name: 'Shelf',
      path: '/shelf',
      builder: (_, _) => const AutoRouter(),
      children: [_page('Aisle', ''), _refused('Locked', 'locked')],
    ),
    _refused('Closed', '/closed'),
    NamedRouteDef(
      name: 'Depot',
      path: '/depot',
      builder: (_, _) => DeferredWidget(
        () => library.future,
        () => const AutoTabsRouter(
          routes: [NamedRoute<Object?>('Dock'), NamedRoute<Object?>('Yard')],
        ),
        placeholder: const Text('Loading'),
      ),
      children: [
        _page('Dock', 'dock'),
        _page('Yard', 'yard'),
        _page('Vault', 'hidden'),
      ],
    ),
  ];
}

class _App {
  new(this.tester) {
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final router = _Router(browser);

  // The page on top, the pages of the stack and the browser's entries.
  String get shown =>
      '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] ${browser.held}';

  Future<void> openA({required bool includePrefixMatches}) async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(
        rebuildStackOnDeepLink: true,
        includePrefixMatches: includePrefixMatches,
      ),
    );
    await browser.settle(tester);
    unawaited(router.push(const NamedRoute('A')));
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

  // The page shown after each of [presses], until one has no entry.
  Future<List<String>> walk(List<bool Function()> presses) async {
    final shownAfter = <String>[];
    for (final press in presses) {
      if (!press()) break;
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }
}

void main() {
  for (final includePrefixMatches in [false, true]) {
    testWidgets('Back after a typed url shows A alone, then Home alone, '
        'prefix matches $includePrefixMatches', (tester) async {
      final app = _App(tester);
      await app.openA(includePrefixMatches: includePrefixMatches);
      await app.typeUrl('/b');
      final link = includePrefixMatches ? 'B [Home B]' : 'B [B]';
      expect(app.shown, '$link / /a >/b');
      final asked = app.browser.asked.length;

      final back = app.browser.didPressBack;
      final forward = app.browser.didPressForward;
      expect(await app.walk([back, back, forward, forward]), [
        'A [A] / >/a /b',
        'Home [Home] >/ /a /b',
        'A [Home A] / >/a /b',
        'B [Home A B] / /a >/b',
      ]);
      expect(app.browser.asked.skip(asked), isEmpty);
    });

    testWidgets('A typed url the tabs turn down steps back to A, and back '
        'shows Home once, prefix matches $includePrefixMatches', (
      tester,
    ) async {
      final app = _App(tester);
      await app.openA(includePrefixMatches: includePrefixMatches);
      final asked = app.browser.asked.length;
      await app.typeUrl('/store/hidden');

      expect(app.shown, 'A [Home A] / >/a /store/hidden');
      expect(app.browser.asked.skip(asked), ['go -1']);
      final back = app.browser.didPressBack;
      expect(await app.walk([back, back]), ['Home [Home] >/ /a /store/hidden']);
      expect(await app.walk([app.browser.didPressForward]), [
        'A [Home A] / >/a /store/hidden',
      ]);
      expect(app.browser.asked.skip(asked + 1), isEmpty);
    });
  }

  for (final (url, written, linkPage, walk) in [
    (
      '/store/account',
      'replace /store/shop',
      'Shop [Store] / /a >/store/shop',
      ['A [A] / >/a /store/shop', 'Home [Home] >/ /a /store/shop'],
    ),
    (
      '/shelf/locked',
      'replace /shelf',
      'Aisle [Shelf] / /a >/shelf',
      ['A [A] / >/a /shelf', 'Home [Home] >/ /a /shelf'],
    ),
  ]) {
    testWidgets('A typed url whose nested guard says no keeps its page on '
        'the typed entry, and back shows A alone: $url', (tester) async {
      final app = _App(tester);
      await app.openA(includePrefixMatches: false);
      final asked = app.browser.asked.length;
      await app.typeUrl(url);
      expect(app.shown, linkPage);
      expect(app.browser.asked.skip(asked), [written]);

      final back = app.browser.didPressBack;
      expect(await app.walk([back, back, back]), walk);
      expect(app.browser.asked.skip(asked + 1), isEmpty);
    });
  }

  // A typed url that the app keeps out of the address bar, which the tabs
  // turn down: the writer steps back to A at once, as the url has no entry
  // of the app's, and the turn-down moves the app's first entry back while
  // that step is on its way. Was: the step noted /a at Home's entry, so the
  // app wrote / and pushed /a, which dropped the typed entry.
  testWidgets('A typed url kept out of the address bar that the tabs turn '
      'down keeps its entry ahead', (tester) async {
    final app = _App(tester);
    await app.openA(includePrefixMatches: false);
    final asked = app.browser.asked.length;
    await app.typeUrl('/keptstore/hidden');

    expect(
      (app.shown, app.browser.asked.skip(asked).join(', ')),
      ('A [Home A] / >/a /keptstore/hidden', 'go -1'),
    );
  });

  testWidgets('A push after a typed url adds an entry after its entry', (
    tester,
  ) async {
    final app = _App(tester);
    await app.openA(includePrefixMatches: false);
    await app.typeUrl('/b');
    final asked = app.browser.asked.length;

    unawaited(app.router.push(const NamedRoute('C')));
    await app.browser.settle(tester);

    expect(app.shown, 'C [B C] / /a /b >/c');
    expect(app.browser.asked.skip(asked), ['push /c']);
  });

  for (final (url, includePrefixMatches) in [
    ('/closed', false),
    ('/store/hidden', false),
    ('/store/hidden', true),
  ]) {
    testWidgets('Forward onto the entry of a typed url the app turned down '
        'opens the url again, and the app turns it down again, with A and '
        'its dialog kept: $url, prefix matches $includePrefixMatches', (
      tester,
    ) async {
      final app = _App(tester);
      await app.openA(includePrefixMatches: includePrefixMatches);
      await app.typeUrl(url);
      expect(app.shown, 'A [Home A] / >/a $url');
      final elementOfA = tester.element(find.text('A'));
      final dialogClosed = Completer<void>();
      unawaited(
        showDialog<void>(
          context: app.router.navigatorKey.currentContext!,
          builder: (_) => const Text('Dialog'),
        ).then(dialogClosed.complete),
      );
      await app.browser.settle(tester);
      final asked = app.browser.asked.length;

      final forward = app.browser.didPressForward;
      expect(await app.walk([forward, forward]), [
        'A [Home A] / >/a $url',
        'A [Home A] / >/a $url',
      ]);
      expect(app.browser.asked.skip(asked), ['go -1', 'go -1']);
      expect(
        (
          find.text('Dialog').evaluate().length,
          dialogClosed.isCompleted,
          identical(tester.element(find.text('A')), elementOfA),
        ),
        (1, false, true),
      );
    });
  }

  testWidgets('A jump over the entry of a typed url the tabs turned down '
      'ends on A, as a forward onto that entry does', (tester) async {
    final app = _App(tester);
    await app.openA(includePrefixMatches: false);
    await app.typeUrl('/depot/hidden');
    unawaited(app.router.push(const NamedRoute('C')));
    await app.browser.settle(tester);
    unawaited(app.router.maybePop());
    await app.browser.settle(tester);
    app.router.library.complete();
    await app.browser.settle(tester);
    final beforeJump = app.shown;
    final asked = app.browser.asked.length;

    app.browser.didJump(2);
    await app.browser.settle(tester);

    expect(
      (beforeJump, app.shown, app.browser.asked.skip(asked).join(', ')),
      (
        'A [Home A] / >/a /depot/hidden /c',
        'A [Home A] / >/a /depot/hidden /c',
        'go -2',
      ),
    );
  });

  testWidgets('A push while the deferred tabs page of a turned-down url '
      'loads leaves one entry for each page', (tester) async {
    final app = _App(tester);
    await app.openA(includePrefixMatches: false);
    await app.typeUrl('/depot/hidden');
    unawaited(app.router.push(const NamedRoute('C')));
    await app.browser.settle(tester);
    app.router.library.complete();
    await app.browser.settle(tester);

    expect(app.shown, 'C [Home A C] / /a >/c');
    final back = app.browser.didPressBack;
    expect(await app.walk([back, back, back]), [
      'A [Home A] / >/a /c',
      'Home [Home] >/ /a /c',
    ]);
  });
}
