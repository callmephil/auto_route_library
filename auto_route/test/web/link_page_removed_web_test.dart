// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import 'browser_history.dart';

// On the web, pages a link opens together share the link's one browser
// entry, held by the link's page on top. When the app takes that page away
// without a pop, as removeWhere does, while pages it opened with the link
// stay, the nearest of them takes the link's entry over, so the back button
// still reaches every page left open, one press each.
//
// Before, the entry left with its page and the pages under it had none:
// opened at the link /b (Home, A, B), a push of C and a removal of B left
// the browser on its first entry, so back left the app with A still open,
// and typed over Home, one back press from C closed C and A together.
//
// The steps: the link /b, which a deepLinkBuilder opens as Home, A and B,
// at launch or typed into the address bar over Home; then a push of C, or
// none, and the removal of B or of A. Removing a page that only shares the
// entry worked before and still does, as do pages the app put on with
// pushAll, which have an entry each.
//
// Native behavior this holds to: Flutter's Navigator, where removeRoute
// leaves the routes below and above it, and the system back from C then
// shows A; and the browser, which can't drop an entry, so the link's entry
// is the one A can have.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/s',
      builder: (_, _) => const AutoRouter(),
      children: [
        for (final name in ['ShellARoute', 'ShellBRoute'])
          NamedRouteDef(
            name: name,
            path: name == 'ShellARoute' ? 'a' : 'b',
            builder: (_, _) => Text(name),
          ),
      ],
    ),
  ],
);

// The root stack, with the pages of the shell's router in brackets.
String _stack(RootStackRouter router) {
  String names(StackRouter stack) =>
      stack.stack.map((page) => page.name?.replaceAll('Route', '')).join(' ');
  final shell = router.innerRouterOf<StackRouter>('ShellRoute');
  final root = names(router);
  return shell == null ? root : '$root [${names(shell)}]';
}

Widget _app(RootStackRouter router) => MaterialApp.router(
  routerConfig: router.config(
    deepLinkBuilder: (link) => switch (link.path) {
      '/b' => const DeepLink([
        NamedRoute('HomeRoute'),
        NamedRoute('ARoute'),
        NamedRoute('BRoute'),
      ]),
      '/s/b' => const DeepLink([
        NamedRoute('HomeRoute'),
        NamedRoute(
          'ShellRoute',
          children: [NamedRoute('ShellARoute'), NamedRoute('ShellBRoute')],
        ),
      ]),
      _ => link,
    },
  ),
);

// The removal, then each press of the back button down to the app's first
// entry: the browser entry counted from the app's first, the url in the
// address bar, and the stack.
Future<List<String>> _removeAndWalkBack(
  WidgetTester tester,
  RootStackRouter router, {
  required int first,
  required String removed,
}) async {
  String reading() =>
      '(${browserSerialCount - first}, $browserPath, ${_stack(router)})';
  router.removeWhere((route) => route.name == removed);
  await settleBrowser(tester);
  final readings = [reading()];
  for (var i = 0; i < 4 && browserSerialCount > first; i++) {
    await pressBrowserBack(tester);
    readings.add(reading());
  }
  return readings;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Each case: whether the link opens the app or is typed over Home,
  // whether C is pushed over it, the page removed, and the readings after
  // the removal and after each back press.
  final cases = {
    'opened at the link, push C, remove B, the page holding its entry': (
      true,
      true,
      'BRoute',
      ['(1, /c, Home A C)', '(0, /a, Home A)'],
    ),
    'opened at the link, push C, remove A, a page sharing its entry': (
      true,
      true,
      'ARoute',
      ['(1, /c, Home B C)', '(0, /b, Home B)'],
    ),
    'opened at the link, remove A under B': (
      true,
      false,
      'ARoute',
      ['(0, /b, Home B)'],
    ),
    'the link typed over Home, push C, remove B': (
      false,
      true,
      'BRoute',
      ['(2, /c, Home A C)', '(1, /a, Home A)', '(0, /, Home)'],
    ),
    'the link typed over Home, push C, remove A': (
      false,
      true,
      'ARoute',
      ['(2, /c, Home B C)', '(1, /b, Home B)', '(0, /, Home)'],
    ),
    'the link typed over Home, remove A under B': (
      false,
      false,
      'ARoute',
      ['(1, /b, Home B)', '(0, /, Home)'],
    ),
  };

  for (final MapEntry(key: name, value: (atLaunch, pushesC, removed, native))
      in cases.entries) {
    testWidgets(name, (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      final int first;
      if (atLaunch) {
        first = browserSerialCount < 0 ? 0 : browserSerialCount;
        openBrowserAt(tester, '/b');
        await pumpAsRunApp(tester, _app(router));
      } else {
        await tester.pumpWidget(_app(router));
        await settleBrowser(tester);
        first = browserSerialCount;
        await browserMove(tester, () => window.location.hash = '/b');
      }
      await settleBrowser(tester);
      if (pushesC) {
        unawaited(router.push(const NamedRoute('CRoute')));
        await settleBrowser(tester);
      }
      final readings = await _removeAndWalkBack(
        tester,
        router,
        first: first,
        removed: removed,
      );
      debugPrint('$name: after the removal and each back $readings');
      expect(readings, native);
    });
  }

  // The entry's page pops in a router that C covers: its entry stays under
  // C's until the pop is over, and then goes to A.
  testWidgets('opened at the link /s/b, push C, the shell pops B under C', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    final first = browserSerialCount < 0 ? 0 : browserSerialCount;
    openBrowserAt(tester, '/s/b');
    await pumpAsRunApp(tester, _app(router));
    await settleBrowser(tester);
    String reading() =>
        '(${browserSerialCount - first}, $browserPath, ${_stack(router)})';
    final opened = reading();
    unawaited(router.push(const NamedRoute('CRoute')));
    await settleBrowser(tester);
    router.innerRouterOf<StackRouter>('ShellRoute')!.pop();
    await settleBrowser(tester);
    final readings = [reading()];
    for (var i = 0; i < 4 && browserSerialCount > first; i++) {
      await pressBrowserBack(tester);
      readings.add(reading());
    }
    debugPrint('shell: opened $opened; after the pop and each back $readings');
    expect(opened, '(0, /s/b, Home Shell [ShellA ShellB])');
    expect(readings, [
      '(1, /c, Home Shell C [ShellA])',
      '(0, /s/a, Home Shell [ShellA])',
    ]);
  });

  testWidgets('pages put on with pushAll, push C, remove B', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await settleBrowser(tester);
    final first = browserSerialCount;
    unawaited(
      router.pushAll(const [NamedRoute('ARoute'), NamedRoute('BRoute')]),
    );
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('CRoute')));
    await settleBrowser(tester);
    final readings = await _removeAndWalkBack(
      tester,
      router,
      first: first,
      removed: 'BRoute',
    );
    debugPrint('pushAll: after the removal and each back $readings');
    expect(readings, ['(2, /c, Home A C)', '(1, /a, Home A)', '(0, /, Home)']);
  });
}
