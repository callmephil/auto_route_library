// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, after a pop the page left stays ahead in the browser's history,
// and the forward button reopens it, also when the next frame comes before
// the browser has made the step back. The Router's report of the turn's url,
// a replace since ffd3a4e7, then overwrote the entry the browser was still
// standing on with the url of the page under; about every second pop lost
// its forward entry. The report now waits until the browser has landed.
//
// Native behavior this holds to: the HTML History API; after history.back()
// the entry left stays ahead, and history.forward() returns to it.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

void main() {
  useRealBrowserHistory();
  useLiveFrames();
  setUp(rewindBrowserHistory);

  // Steps: open the pages over Home, make the pops, run a frame before the
  // browser has stepped back, let it land, then press the browser's forward
  // button once for each page the pops closed.
  for (final (label, opens, pops) in [
    ('a pop', ['ARoute'], (StackRouter router) => router.pop()),
    (
      'popUntilRoot from the third page',
      ['ARoute', 'BRoute'],
      (StackRouter router) => router.popUntilRoot(),
    ),
    (
      'popUntilRouteWithName from the third page',
      ['ARoute', 'BRoute'],
      (StackRouter router) => router.popUntilRouteWithName('HomeRoute'),
    ),
  ]) {
    testWidgets('On web, $label with the frame before the step back keeps '
        'the pages left ahead', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final home = browserSerialCount;
      for (final name in opens) {
        unawaited(router.push(NamedRoute(name)));
        await settleBrowser(tester);
      }
      // Whether the browser reported its step back.
      final landed = window.onPopState.first.then((_) => true);
      pops(router);
      await runFrameBeforeBrowserMoves(tester);
      await landed.timeout(const Duration(seconds: 2), onTimeout: () => false);
      await settleBrowser(tester);
      final afterPops = (browserSerialCount - home, browserPath);
      // The Chrome runner doesn't print a failed expectation.
      printOnFailure('after the pops: $afterPops');
      // Checked before the browser moves forward.
      expect(afterPops, (0, '/'));

      final ahead = <String>[];
      for (var i = 0; i < opens.length; i++) {
        await pressBrowserForward(tester);
        ahead.add(browserPath);
      }
      printOnFailure('forward: $ahead');
      expect(ahead, [for (final name in opens) '/${name[0].toLowerCase()}']);
    });
  }
}
