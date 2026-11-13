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

// On the web, a push and a replace of the pushed page in one frame write one
// new browser entry: the page under keeps its own. The router writes the url
// once per frame, after it; it used to write that one url with the last
// change's kind, a replace, so the replaced page's entry was the one under,
// Home's, and the browser's back button had nowhere to go.
//
// Native behavior this holds to: the HTML History API. pushState then
// replaceState leaves the entry before as it was, and one new entry holding
// the last url. Off the web the router's own history records each change as
// it comes, and back from B already goes to Home there.
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

// The browser's entry and url, the names on the router's stack, and the top
// page's arguments, as one value, so a failure prints them all.
(int, String, String, Object?) _shown(RootStackRouter router) => (
  browserSerialCount,
  browserPath,
  router.stack.map((m) => m.name).join(' '),
  router.current.args,
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: push A, and before the next frame, after an await that completes
  // at once, replace A with B and arguments the url can't carry; then press
  // the browser's back button, then its forward button.
  // Was: B's url went over Home's entry, and back had no entry to go to.
  // Forward then reopened B without its arguments, since the history kept
  // B one entry past the one the browser wrote.
  testWidgets('On web, a push and a replace in one frame keep the entry of '
      'the page under', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;

    unawaited(router.push(const NamedRoute('ARoute')));
    await Future<void>.delayed(.zero);
    unawaited(router.replace(const NamedRoute('BRoute', args: 'draft 7')));
    await settleBrowser(tester);
    final afterReplace = _shown(router);
    // The Chrome runner doesn't print a failed expectation.
    printOnFailure('after the replace: $afterReplace');
    // Checked before the browser moves: without the fix the app's page has
    // no entry to go back to, and back would leave the test page, so nothing
    // would ever answer the step.
    expect(afterReplace, (home + 1, '/b', 'HomeRoute BRoute', 'draft 7'));

    // After back, and after forward.
    final readings = <(int, String, String, Object?)>[];
    for (final move in [pressBrowserBack, pressBrowserForward]) {
      await move(tester);
      readings.add(_shown(router));
    }
    printOnFailure('after back and forward: $readings');
    expect(readings, [
      (home, '/', 'HomeRoute', null),
      (home + 1, '/b', 'HomeRoute BRoute', 'draft 7'),
    ]);
  });
}
