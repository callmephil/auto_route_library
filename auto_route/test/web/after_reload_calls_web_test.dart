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

// On the web, after a reload of the page the app starts on the entry the
// browser stands on and knows nothing of the entries under it. Whatever the
// app then calls, it ends on the page the calls ask for, and the browser on
// that page's url, on the entry the app's own pops would reach: never under
// the entry the app was reloaded on, where a page from before the reload
// is.
//
// Before the web history became the browser's one writer, a call that
// leaves one page, such as pushAndPopUntil with no page kept or pops
// followed by a replace in one turn, could step the browser back by the
// number of pages closed and end on an entry from before the reload, or
// write the new page's url on a later entry.
//
// Native behavior this holds to: Flutter's Navigator, where
// pushAndRemoveUntil leaves only the new route, and the HTML History API,
// where a reload keeps the session history and the document starts again on
// the entry it was on.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
      ('ERoute', '/e'),
      ('LoginRoute', '/login'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

String _names(StackRouter router) =>
    router.stack.map((page) => page.name?.replaceAll('Route', '')).join(' ');

Future<void> _wait(WidgetTester tester) async {
  await settleBrowser(tester);
  await tester.pump(const Duration(milliseconds: 300));
  await settleBrowser(tester);
}

typedef _Step = FutureOr<void> Function(
  WidgetTester tester,
  StackRouter router,
);

_Step _push(String name) =>
    (_, router) => unawaited(router.push(NamedRoute(name)));
_Step _replaceWith(String name) =>
    (_, router) => unawaited(router.replace(NamedRoute(name)));
_Step _clearTo(String name) =>
    (_, router) => unawaited(
      router.pushAndPopUntil(NamedRoute(name), predicate: (_) => false),
    );
Future<void> _browserBack(WidgetTester tester, StackRouter _) =>
    pressBrowserBack(tester);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Home, A and B in the browser, written by an app that is then gone.
  Future<void> openedBeforeReload(WidgetTester tester) async {
    final before = _router();
    await pumpRouterConfigApp(tester, before.config());
    await settleBrowser(tester);
    for (final name in ['ARoute', 'BRoute']) {
      unawaited(before.push(NamedRoute(name)));
      await settleBrowser(tester);
    }
    await tester.pumpWidget(const SizedBox());
    await settleBrowser(tester);
    before.dispose();
  }

  // A reload on B: a new app, a new router, the browser still on B's entry.
  Future<RootStackRouter> reloadedOnB(WidgetTester tester) async {
    await openedBeforeReload(tester);
    final router = _router();
    addTearDown(router.dispose);
    openBrowserAt(tester, '/b');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(routerConfig: router.config()),
    );
    return router;
  }

  // Steps: open A and B over Home, reload on B, then make the calls. Each is
  // a turn of its own unless it is a list, which is one turn.
  // Expected: the stack, the url, and the entry counted from the one the app
  // was reloaded on.
  for (final (label, steps, stack, url, entry)
      in <(String, List<Object>, String, String, int)>[
        (
          'push C, push D, clear to Login',
          [_push('CRoute'), _push('DRoute'), _clearTo('LoginRoute')],
          'Login',
          '/login',
          0,
        ),
        (
          'push C, then popUntilRoot and replace with D in one turn',
          [
            _push('CRoute'),
            <_Step>[
              (_, router) => router.popUntilRoot(),
              (_, router) =>
                  unawaited(router.replace(const NamedRoute('DRoute'))),
            ],
          ],
          'D',
          '/d',
          0,
        ),
        (
          'push C, push D, then pop, pop and replace with E in one turn',
          [
            _push('CRoute'),
            _push('DRoute'),
            <_Step>[
              (_, router) => router.pop(),
              (_, router) => router.pop(),
              (_, router) =>
                  unawaited(router.replace(const NamedRoute('ERoute'))),
            ],
          ],
          'E',
          '/e',
          0,
        ),
        (
          'push C, clear to Login, then push D',
          [_push('CRoute'), _clearTo('LoginRoute'), _push('DRoute')],
          'Login D',
          '/d',
          1,
        ),
        (
          'push C, then clear to Login and push D in one turn',
          [
            _push('CRoute'),
            <_Step>[_clearTo('LoginRoute'), _push('DRoute')],
          ],
          'Login D',
          '/d',
          1,
        ),
        (
          'push C, clear to Login, clear to D',
          [_push('CRoute'), _clearTo('LoginRoute'), _clearTo('DRoute')],
          'D',
          '/d',
          0,
        ),
        (
          'push C, the browser goes back, replace with D',
          [_push('CRoute'), _browserBack, _replaceWith('DRoute')],
          'D',
          '/d',
          0,
        ),
        (
          'push C, push D, the browser goes back, clear to Login',
          [
            _push('CRoute'),
            _push('DRoute'),
            _browserBack,
            _clearTo('LoginRoute'),
          ],
          'Login',
          '/login',
          0,
        ),
        (
          'clear to Login right away, push C, clear to D',
          [_clearTo('LoginRoute'), _push('CRoute'), _clearTo('DRoute')],
          'D',
          '/d',
          0,
        ),
      ]) {
    testWidgets('On web, after a reload on the third entry: $label', (
      tester,
    ) async {
      final router = await reloadedOnB(tester);
      final reloadedAt = browserSerialCount;
      for (final step in steps) {
        if (step is List<_Step>) {
          for (final call in step) {
            await call(tester, router);
          }
        } else {
          await (step as _Step)(tester, router);
        }
        await _wait(tester);
      }
      expect(tester.takeException(), isNull);
      expect(
        '${_names(router)}, browser ${browserSerialCount - reloadedAt} '
            '$browserPath, app url ${router.currentUrl}',
        '$stack, browser $entry $url, app url $url',
      );
    });
  }
}
