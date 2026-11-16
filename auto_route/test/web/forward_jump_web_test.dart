// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, a jump forward over several entries, as from the list a long
// press on the forward button shows, opens the page of the entry landed on,
// as a link to it does. That page is then over the page shown before, on
// the entry over that page's, so the back button shows the page before.
//
// Before the web history became the browser's one writer, the browser
// stayed on the entry landed on, and the back button went to the entries
// passed over, of pages the app had closed.
//
// Native behavior this holds to: the HTML History API, where history.go(3)
// lands on the third entry ahead; and Flutter's Navigator, where back
// closes the page on top and shows the one under it.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: open A, B and C over Home, call popUntilRoot, then go three
  // entries forward at once and press the back button.
  testWidgets('On web, a jump forward over several entries opens the page '
      'of the entry landed on, and back then shows the page before', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    for (final name in ['ARoute', 'BRoute', 'CRoute']) {
      unawaited(router.push(NamedRoute(name)));
      await settleBrowser(tester);
    }
    router.popUntilRoot();
    await settleBrowser(tester);

    await browserMove(tester, () => window.history.go(3));
    expect(router.stack.map((page) => page.name), ['HomeRoute', 'CRoute']);
    expect((browserSerialCount - home, browserPath), (1, '/c'));

    await pressBrowserBack(tester);
    expect(router.stack.map((page) => page.name), ['HomeRoute']);
    expect((browserSerialCount - home, browserPath), (0, '/'));
  });
}
