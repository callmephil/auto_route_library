@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, with rebuildStackOnDeepLink, back after a url typed
// into the address bar shows the page of each entry that the link closed
// alone, and no press changes an entry (callmephil/auto_route_library#43).
// A typed url the tabs turn down, /store/hidden, leaves the browser on the
// entry of A, with no entry but the user's own added, also after forward
// onto it, which keeps the dialog over A, or after a jump over it. A push
// while its deferred tabs page loads stays on top, on an entry after A's
// (callmephil/auto_route_library#58).
// The steps, what was seen and what should be seen are those of the
// headless test on the VM: test/rebuild_stack_typed_url_back_test.dart.
// Prefix matches are off, as on the web by default.
//
// Native behavior this holds to: the HTML standard's session history, where
// a traversal goes to another entry and adds or changes none.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// [library] is what the deferred Depot page loads before its tabs.
RootStackRouter _router([Future<void>? library]) => .build(
  routes: [
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
        _page('Account', 'account'),
        _page('Hidden', 'hidden'),
      ],
    ),
    NamedRouteDef(
      name: 'KeptStore',
      path: '/keptstore',
      builder: (_, _) =>
          const AutoTabsRouter(routes: [NamedRoute<Object?>('KeptShop')]),
      children: [_page('KeptShop', 'shop'), _page('KeptHidden', 'hidden')],
    ),
    NamedRouteDef(
      name: 'Depot',
      path: '/depot',
      builder: (_, _) => DeferredWidget(
        () => library ?? Future.value(),
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
  ],
);

// The page on top, the pages of the stack, the browser's url and its entry,
// counted from [home].
String _shown(RootStackRouter router, int home) =>
    '${router.topRoute.name} '
    '[${router.stack.map((page) => page.name).join(' ')}] '
    '$browserPath ${browserSerialCount - home}';

// Opens Home, then A; answers the number of Home's entry.
Future<int> _openA(WidgetTester tester, RootStackRouter router) async {
  await pumpRouterConfigApp(
    tester,
    router.config(rebuildStackOnDeepLink: true),
  );
  await settleBrowser(tester);
  final home = browserSerialCount;
  unawaited(router.push(const NamedRoute<Object?>('A')));
  await settleBrowser(tester);
  return home;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('Back after a typed url shows A alone, then Home alone, and '
      'forward walks the same entries up to B', (tester) async {
    final router = _router();
    final home = await _openA(tester, router);
    await browserMove(tester, () => window.location.hash = '/b');
    expect(_shown(router, home), 'B [B] /b 2');

    final walk = <String>[];
    for (var i = 0; i < 2 && browserSerialCount > home; i++) {
      await pressBrowserBack(tester);
      walk.add(_shown(router, home));
    }
    for (var i = 0; i < 2; i++) {
      await pressBrowserForward(tester);
      walk.add(_shown(router, home));
    }
    expect(walk, [
      'A [A] /a 1',
      'Home [Home] / 0',
      'A [Home A] /a 1',
      'B [Home A B] /b 2',
    ]);
  });

  testWidgets('A typed url the tabs turn down steps back to A, and back '
      'shows Home once', (tester) async {
    final router = _router();
    final home = await _openA(tester, router);
    final length = browserEntryCount;
    await browserMove(tester, () => window.location.hash = '/store/hidden');
    expect(_shown(router, home), 'A [Home A] /a 1');
    expect(browserEntryCount, length + 1);

    final walk = <String>[];
    await pressBrowserBack(tester);
    walk.add(_shown(router, home));
    await pressBrowserForward(tester);
    walk.add(_shown(router, home));
    expect(walk, ['Home [Home] / 0', 'A [Home A] /a 1']);
  });

  // A typed url that neglectWhen keeps out of the address bar, which the
  // tabs turn down, with the frame that builds the tabs before the browser
  // lands from the step back to A, as in an app. Was: the app wrote / and
  // pushed /a, which dropped the typed entry.
  group('With the frame before the step back lands', () {
    useLiveFrames();

    testWidgets('A typed url kept out of the address bar that the tabs turn '
        'down keeps its entry ahead', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(
          rebuildStackOnDeepLink: true,
          neglectWhen: (location) => location?.startsWith('/kept') ?? false,
        ),
      );
      await settleBrowser(tester);
      final home = browserSerialCount;
      unawaited(router.push(const NamedRoute<Object?>('A')));
      await settleBrowser(tester);
      final length = browserEntryCount;
      final typed = window.onPopState.first;
      window.location.hash = '/keptstore/hidden';
      await typed.timeout(const Duration(seconds: 5));
      final steppedBack = window.onPopState.first.then((_) => true);
      await runFrameBeforeBrowserMoves(tester);
      final didStep = await steppedBack.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      await settleBrowser(tester);

      expect(
        (didStep, _shown(router, home), browserEntryCount - length),
        (true, 'A [Home A] /a 1', 1),
      );
    });
  });

  testWidgets('Forward onto the entry of a typed url the tabs turned down '
      'shows A again, keeps its dialog and adds no entry', (tester) async {
    final router = _router();
    final home = await _openA(tester, router);
    final length = browserEntryCount;
    await browserMove(tester, () => window.location.hash = '/store/hidden');
    final elementOfA = tester.element(find.text('A'));
    final dialogClosed = Completer<void>();
    unawaited(
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const Text('Dialog'),
      ).then(dialogClosed.complete),
    );
    await settleBrowser(tester);

    final walk = <String>[];
    for (var press = 0; press < 2; press++) {
      await pressBrowserForward(tester);
      walk.add(_shown(router, home));
    }
    expect(walk, ['A [Home A] /a 1', 'A [Home A] /a 1']);
    expect(
      (
        browserEntryCount - length,
        find.text('Dialog').evaluate().length,
        dialogClosed.isCompleted,
        identical(tester.element(find.text('A')), elementOfA),
      ),
      (1, 1, false, true),
    );
  });

  testWidgets('A jump over the entry of a typed url the tabs turned down '
      'ends on A', (tester) async {
    final library = Completer<void>();
    final router = _router(library.future);
    final home = await _openA(tester, router);
    final length = browserEntryCount;
    await browserMove(tester, () => window.location.hash = '/depot/hidden');
    unawaited(router.push(const NamedRoute<Object?>('C')));
    await settleBrowser(tester);
    unawaited(router.maybePop());
    await settleBrowser(tester);
    library.complete();
    await settleBrowser(tester);
    final beforeJump = _shown(router, home);

    await browserMove(tester, () => window.history.go(2));
    expect(
      (beforeJump, _shown(router, home), browserEntryCount - length),
      ('A [Home A] /a 1', 'A [Home A] /a 1', 2),
    );
  });

  testWidgets('A push while the deferred tabs page of a turned-down url '
      'loads leaves one entry for each page', (tester) async {
    final library = Completer<void>();
    final router = _router(library.future);
    final home = await _openA(tester, router);
    final length = browserEntryCount;
    await browserMove(tester, () => window.location.hash = '/depot/hidden');
    unawaited(router.push(const NamedRoute<Object?>('C')));
    await settleBrowser(tester);
    library.complete();
    await settleBrowser(tester);
    expect(_shown(router, home), 'C [Home A C] /c 2');
    expect(browserEntryCount, length + 1);

    final walk = <String>[];
    while (browserSerialCount > home) {
      await pressBrowserBack(tester);
      walk.add(_shown(router, home));
    }
    expect(walk, ['A [Home A] /a 1', 'Home [Home] / 0']);
  });
}
