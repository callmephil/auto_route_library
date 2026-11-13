// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, after popUntilRoot or popUntil closes several pages at once,
// the browser's back button reopens none of them: the browser is stepped back
// to the entry of the page now on top. The web history used to look only one
// entry back for that page; when that entry held another closed page, it
// wrote the page now on top over the current entry instead, so the entries of
// the closed pages stayed behind it and back reopened them.
//
// Native behavior this holds to: Android's popBackStack to a destination and
// iOS's popToViewController drop every screen they close from the back stack.
// The browser can't delete entries; history.go(-n) back to the entry of the
// page now shown is how a web page drops them, keeping them ahead for the
// forward button as a user's own back presses would.
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

// Opens A, B and C over Home and returns the router and Home's entry.
Future<(RootStackRouter, int)> _pumpFourPages(WidgetTester tester) async {
  final router = _router();
  await pumpRouterConfigApp(tester, router.config());
  await settleBrowser(tester);
  final home = browserSerialCount;
  for (final name in ['ARoute', 'BRoute', 'CRoute']) {
    unawaited(router.push(NamedRoute(name)));
    await settleBrowser(tester);
  }
  return (router, home);
}

// The browser's entry and url, and the names on the router's stack, as one
// value, so a failure prints all three.
(int, String, String) _shown(RootStackRouter router) => (
  browserSerialCount,
  browserPath,
  router.stack.map((m) => m.name).join(' '),
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: push A, B and C over Home, then call popUntilRoot.
  // Was: the browser stayed on C's entry, now showing '/', and its back
  // button reopened B.
  testWidgets('On web, popUntilRoot steps the browser back to the entry of '
      'Home', (tester) async {
    final (router, home) = await _pumpFourPages(tester);

    router.popUntilRoot();
    await settleBrowser(tester);
    expect(_shown(router), (home, '/', 'HomeRoute'));
  });

  // Steps: push A, B and C over Home, pop until A with
  // popUntilRouteWithName, then press the browser's back button.
  // Was: the browser stayed on C's entry, now showing '/a', and its back
  // button reopened B.
  testWidgets('On web, back after popUntil goes to the page under the one '
      'it stopped at', (tester) async {
    final (router, home) = await _pumpFourPages(tester);

    router.popUntilRouteWithName('ARoute');
    await settleBrowser(tester);
    final afterPop = _shown(router);
    // The Chrome runner doesn't print a failed expectation.
    printOnFailure('after popUntil: $afterPop');
    // Checked before the browser moves, so a missing step back fails here.
    expect(afterPop, (home + 1, '/a', 'HomeRoute ARoute'));

    await pressBrowserBack(tester);
    printOnFailure('after back: ${_shown(router)}');
    expect(_shown(router), (home, '/', 'HomeRoute'));
  });
}
