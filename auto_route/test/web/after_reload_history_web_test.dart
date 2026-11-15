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

// On the web, after a reload, a call that takes away the page the app started
// on ends on the page it asks for, never on an entry from before the reload.
// A reloaded app starts on the entry the browser stands on and knows nothing
// of the entries under it, so it must not step back onto one: the browser's
// report of it would open that old page as the user's own back step. A pin
// for the web history's next rework.
//
// Native behavior this holds to: the HTML History API; a page knows the
// entries of the session history only as it moves through them, and a
// reloaded document has the entries before it, which it did not write.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
      ('LoginRoute', '/login'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

// Home, A and B in the browser, then a reload on B: a second app on the same
// browser history, the browser still on B's entry, the third.
Future<RootStackRouter> _reloadedOnB(WidgetTester tester) async {
  // The app before the reload, and the app after it.
  final [first, router] = [for (var i = 0; i < 2; i++) _router()];
  await pumpRouterConfigApp(tester, first.config());
  await settleBrowser(tester);
  for (final name in ['ARoute', 'BRoute']) {
    unawaited(first.push(NamedRoute(name)));
    await settleBrowser(tester);
  }
  await tester.pumpWidget(const SizedBox());
  await settleBrowser(tester);
  first.dispose();

  addTearDown(router.dispose);
  openBrowserAt(tester, '/b');
  await pumpAsRunApp(tester, MaterialApp.router(routerConfig: router.config()));
  return router;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: Home, push A, push B, reload on B, push C, then the calls.
  for (final (label, calls, expected) in [
    (
      'pushAndPopUntil the login page over nothing',
      (StackRouter router) => unawaited(
        router.pushAndPopUntil(
          const NamedRoute('LoginRoute'),
          predicate: (_) => false,
        ),
      ),
      ('LoginRoute', '/login'),
    ),
    (
      'a pop and a replace with D in one turn',
      (StackRouter router) {
        router.pop();
        unawaited(router.replace(const NamedRoute('DRoute')));
      },
      ('DRoute', '/d'),
    ),
  ]) {
    testWidgets('On web, after a reload: push C, then $label', (tester) async {
      final router = await _reloadedOnB(tester);
      final reloadedAt = browserSerialCount;
      unawaited(router.push(const NamedRoute('CRoute')));
      await settleBrowser(tester);

      calls(router);
      await settleBrowser(tester);
      final shown = (
        router.stack.map((page) => page.name).join(' '),
        browserPath,
      );
      // The Chrome runner doesn't print a failed expectation.
      printOnFailure(
        'after the calls: $shown, entry ${browserSerialCount - reloadedAt} '
        'from the one reloaded at',
      );
      expect((shown, browserSerialCount >= reloadedAt), (expected, true));
    });
  }
}
