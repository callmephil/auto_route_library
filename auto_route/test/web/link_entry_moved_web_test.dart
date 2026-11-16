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

// On the web, the browser entry of the pages a link opened together moves
// to another page when the link's page leaves from the top, by a pop, a
// removeLast or a replace: the page that takes its place holds it, and the
// pages under it share it with that page. Removing that page later from
// under another page then hands the entry to the nearest page that shared
// it, as removing the link's own page does. A page kept out of the address
// bar (neglectWhen) gets no browser entry, so the entry goes to the nearest
// sharing page that is not kept out.
//
// Before, the pages under it still named the page that had left as the one
// whose entry they shared, so the later removal dropped the entry and they
// had none: opened at the link /b (Home, A, B), a pop of B, a push of C and
// a removal of A left the browser on its first entry, so back left the app
// with Home still open.
//
// The steps: the link /b, which a deepLinkBuilder opens as Home, A and B,
// at launch, or the link /c (Home, A, B, C) typed over Home; the link's
// page leaves from the top; a push; the removal of the page that took the
// link's entry; then the back button down to the app's first entry.
//
// Native behavior this holds to: Flutter's Navigator, where removeRoute
// leaves the routes below and above it and the system back then shows the
// route under the top; and the browser, which can't drop an entry, so the
// link's entry is the one the pages it opened can have.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

String _stack(RootStackRouter router) =>
    router.stack.map((page) => page.name?.replaceAll('Route', '')).join(' ');

Widget _app(
  RootStackRouter router, {
  bool Function(String? location)? neglectWhen,
}) => MaterialApp.router(
  routerConfig: router.config(
    neglectWhen: neglectWhen,
    deepLinkBuilder: (link) => switch (link.path) {
      '/b' => const DeepLink([
        NamedRoute('HomeRoute'),
        NamedRoute('ARoute'),
        NamedRoute('BRoute'),
      ]),
      '/c' => const DeepLink([
        NamedRoute('HomeRoute'),
        NamedRoute('ARoute'),
        NamedRoute('BRoute'),
        NamedRoute('CRoute'),
      ]),
      _ => link,
    },
  ),
);

// Opens the app at [link], or types [link] over Home with [isTyped], runs
// [steps] with the browser settled after each, and returns the reading
// then and after each back press down to the app's first entry.
Future<List<String>> _walk(
  WidgetTester tester,
  String link,
  List<void Function(RootStackRouter)> steps, {
  bool isTyped = false,
  bool Function(String? location)? neglectWhen,
}) async {
  final router = _router();
  addTearDown(router.dispose);
  final int first;
  if (isTyped) {
    await tester.pumpWidget(_app(router, neglectWhen: neglectWhen));
    await settleBrowser(tester);
    first = browserSerialCount;
    await browserMove(tester, () => window.location.hash = link);
  } else {
    first = browserSerialCount < 0 ? 0 : browserSerialCount;
    openBrowserAt(tester, link);
    await pumpAsRunApp(tester, _app(router, neglectWhen: neglectWhen));
  }
  await settleBrowser(tester);
  for (final step in steps) {
    step(router);
    await settleBrowser(tester);
  }
  String reading() =>
      '(${browserSerialCount - first}, $browserPath, ${_stack(router)})';
  final readings = [reading()];
  for (var i = 0; i < 4 && browserSerialCount > first; i++) {
    await pressBrowserBack(tester);
    readings.add(reading());
  }
  return readings;
}

void _push(RootStackRouter router, String name) =>
    unawaited(router.push(NamedRoute(name)));

void _remove(RootStackRouter router, String name) =>
    router.removeWhere((route) => route.name == name);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  for (final (label, leave) in [
    ('pop', (RootStackRouter router) => router.pop()),
    ('removeLast', (RootStackRouter router) => router.removeLast()),
  ]) {
    testWidgets('opened at /b: $label B, push C, remove A', (tester) async {
      final readings = await _walk(tester, '/b', [
        leave,
        (router) => _push(router, 'CRoute'),
        (router) => _remove(router, 'ARoute'),
      ]);
      expect(readings, ['(1, /c, Home C)', '(0, /, Home)']);
    });
  }

  testWidgets('opened at /b: replace B with D, push C, remove D', (
    tester,
  ) async {
    final readings = await _walk(tester, '/b', [
      (router) => unawaited(router.replace(const NamedRoute('DRoute'))),
      (router) => _push(router, 'CRoute'),
      (router) => _remove(router, 'DRoute'),
    ]);
    expect(readings, ['(1, /c, Home A C)', '(0, /a, Home A)']);
  });

  testWidgets('/c typed over Home: pop C, push D, remove B', (tester) async {
    final readings = await _walk(tester, '/c', isTyped: true, [
      (router) => router.pop(),
      (router) => _push(router, 'DRoute'),
      (router) => _remove(router, 'BRoute'),
    ]);
    expect(readings, ['(2, /d, Home A D)', '(1, /a, Home A)', '(0, /, Home)']);
  });

  // A, which shared the link's entry, is kept out of the address bar, so
  // Home, the next page under it, takes the entry: back from C skips A, as
  // the README says of a page kept out.
  testWidgets('opened at /b with /a kept out: push C, remove B', (
    tester,
  ) async {
    final readings = await _walk(
      tester,
      '/b',
      neglectWhen: (location) => location == '/a',
      [
        (router) => _push(router, 'CRoute'),
        (router) => _remove(router, 'BRoute'),
      ],
    );
    expect(readings, ['(1, /c, Home A C)', '(0, /, Home)']);
  });
}
