@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, the pages that a typed url with rebuildStackOnDeepLink,
// or replacePath, replace or replaceAll, took off come back under a page
// that the app pushed while the tabs of the new page waited to be built,
// once those tabs turn the route down (callmephil/auto_route_library#58).
// The browser holds one entry for each page and stands on the entry of the
// page on top. The steps, what was seen and what should be seen are those of
// the headless test on the VM:
// test/put_back_under_page_pushed_meanwhile_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.replace keeps the
// routes above the route it replaces, and in the HTML standard's session
// history, history.pushState drops the entries ahead.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// The tabs of Depot and Lazy are built once [gate] completes. They do not
// list Hidden or Attic.
RootStackRouter _router(Future<void> gate) => .build(
  routes: [
    _page('Home', '/'),
    _page('A', '/a'),
    _page('C', '/c'),
    NamedRouteDef(
      name: 'Depot',
      path: '/depot',
      builder: (_, _) => DeferredWidget(
        () => gate,
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
        future: gate,
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
  ],
);

const _depotHidden = NamedRoute<Object?>(
  'Depot',
  children: [NamedRoute<Object?>('Hidden')],
);

// The page on top, the pages of the stack, the browser's url with the path
// state the app shows, and the browser's entry, counted from [home].
String _shown(RootStackRouter router, int home) {
  final state = router.navigationHistory.pathState;
  return '${router.topRoute.name} '
      '[${router.stack.map((page) => page.name).join(' ')}] '
      '$browserPath${state == null ? '' : '#$state'} '
      '${browserSerialCount - home}';
}

enum _Opening { typedUrl, replacePath, replace, replaceAll }

// Opens Home, then A, with [pathState] pushed on A when it is not null. Then
// opens [url] as [opening] does, with rebuildStackOnDeepLink for a typed url,
// pushes C while its page waits for its tabs, and completes [gate]. Answers
// the number of Home's entry, and the history's length before [url].
Future<(int, int)> _openAndPushC(
  WidgetTester tester,
  RootStackRouter router,
  Completer<void> gate,
  _Opening opening,
  String url, {
  Object? pathState,
}) async {
  await pumpRouterConfigApp(
    tester,
    router.config(
      rebuildStackOnDeepLink: opening == .typedUrl,
      includePrefixMatches: false,
    ),
  );
  await settleBrowser(tester);
  final home = browserSerialCount;
  unawaited(router.push(const NamedRoute<Object?>('A')));
  await settleBrowser(tester);
  if (pathState != null) {
    router.navigationHistory.pushPathState(pathState);
    await settleBrowser(tester);
  }
  final length = browserEntryCount;
  final failures = <NavigationFailure>[];
  switch (opening) {
    case .typedUrl:
      await browserMove(tester, () => window.location.hash = url);
    case .replacePath:
      unawaited(router.replacePath(url, onFailure: failures.add));
    case .replace:
      unawaited(router.replace(_depotHidden, onFailure: failures.add));
    case .replaceAll:
      unawaited(router.replaceAll([_depotHidden], onFailure: failures.add));
  }
  await settleBrowser(tester);
  unawaited(router.push(const NamedRoute<Object?>('C')));
  await settleBrowser(tester);
  gate.complete();
  await settleBrowser(tester);
  return (home, length);
}

// What shows after each press of the back button, down to Home's entry.
Future<List<String>> _walkBack(
  WidgetTester tester,
  RootStackRouter router,
  int home,
) async {
  final walk = <String>[];
  while (browserSerialCount > home) {
    await pressBrowserBack(tester);
    walk.add(_shown(router, home));
  }
  return walk;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  for (final (opening, url) in [
    (_Opening.typedUrl, '/depot/hidden'),
    (_Opening.replacePath, '/depot/hidden'),
    (_Opening.replace, '/depot/hidden'),
    (_Opening.replaceAll, '/depot/hidden'),
    (_Opening.replacePath, '/lazy/attic'),
  ]) {
    testWidgets('C stays on top, on its own entry, once the tabs turn down '
        '${opening.name} $url', (tester) async {
      final gate = Completer<void>();
      final router = _router(gate.future);
      final (home, length) = await _openAndPushC(
        tester,
        router,
        gate,
        opening,
        url,
      );
      final afterTurnDown = _shown(router, home);
      final onScreen = find.text('C').evaluate().length;

      expect(
        (afterTurnDown, onScreen, browserEntryCount - length),
        ('C [Home A C] /c 2', 1, 1),
      );
      expect(await _walkBack(tester, router, home), [
        'A [Home A] /a 1',
        'Home [Home] / 0',
      ]);
    });
  }

  testWidgets('A path state that A pushed before the typed url keeps its '
      'entry under C', (tester) async {
    final gate = Completer<void>();
    final router = _router(gate.future);
    final (home, length) = await _openAndPushC(
      tester,
      router,
      gate,
      .typedUrl,
      '/depot/hidden',
      pathState: 'picked',
    );

    expect(
      (_shown(router, home), browserEntryCount - length),
      ('C [Home A C] /c 3', 1),
    );
    expect(await _walkBack(tester, router, home), [
      'A [Home A] /a#picked 2',
      'A [Home A] /a 1',
      'Home [Home] / 0',
    ]);
  });
}
