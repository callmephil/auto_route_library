// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// In a real browser, the pages of a nested router leave the browser's way
// back with the page that holds the router, as a tabs page or a shell,
// when the app closes that page (callmephil/auto_route_library#40). The
// steps, what was seen and what should be seen are those of the headless
// test on the VM: test/back_after_closing_nested_router_page_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where pop and
// removeRoute take the route out with the navigator nested in it, and the
// system back then shows the route under it. The HTML standard's session
// history can't drop an entry, so the page under takes the entry of the
// closed page, or the browser steps back to the entry of that page.

NamedRouteDef _page(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => Scaffold(body: Text(name)),
);

// The routes of fork issue 20 with no guard: Home at '/', the tabs page at
// '/tabs' with the tabs One and Two, and Detail, for the push. And a shell
// with a nested router, for a pop.
RootStackRouter _router() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [NamedRoute('OneRoute'), NamedRoute('TwoRoute')],
        builder: (_, child) => child,
      ),
      children: [_page('OneRoute', 'one'), _page('TwoRoute', 'two')],
    ),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell',
      builder: (_, _) => const AutoRouter(),
      children: [_page('XRoute', ''), _page('YRoute', 'y')],
    ),
    _page('DetailRoute', '/detail'),
  ],
);

Widget _app(RootStackRouter router) =>
    MaterialApp.router(routerConfig: router.config(includePrefixMatches: true));

// The browser entry counted from [first], the url in the address bar, and
// the names on the root's stack.
String _reading(RootStackRouter router, int first) {
  final stack = router.stack
      .map((page) => page.name?.replaceAll('Route', ''))
      .join(' ');
  return '(${browserSerialCount - first}, $browserPath, $stack)';
}

void _push(RootStackRouter router, String name) =>
    unawaited(router.push<Object?>(NamedRoute(name)));

void _removeTabsPage(RootStackRouter router) =>
    router.removeWhere((route) => route.name == 'TabsRoute');

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Shows the app at '/', and returns its router with the number of the
  // app's first entry.
  Future<(RootStackRouter, int)> openAtHome(WidgetTester tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await settleBrowser(tester);
    return (router, browserSerialCount);
  }

  testWidgets('Opened at /tabs/two, push Detail, remove the tabs page: Home '
      "takes the link's entry, and back shows Home", (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    final first = browserSerialCount < 0 ? 0 : browserSerialCount;
    openBrowserAt(tester, '/tabs/two');
    await pumpAsRunApp(tester, _app(router));
    await settleBrowser(tester);
    _push(router, 'DetailRoute');
    await settleBrowser(tester);
    final readings = [_reading(router, first)];

    _removeTabsPage(router);
    await settleBrowser(tester);
    readings.add(_reading(router, first));
    await pressBrowserBack(tester);
    readings.add(_reading(router, first));

    expect(readings, [
      '(1, /detail, Home Tabs Detail)',
      '(1, /detail, Home Detail)',
      '(0, /, Home)',
    ]);
  });

  for (final (name, shown) in [
    ('TabsRoute', '(1, /tabs/one, Home Tabs)'),
    ('ShellRoute', '(1, /shell, Home Shell)'),
  ]) {
    testWidgets('Push $name over Home, then pop it: the browser steps back '
        'to the entry of Home', (tester) async {
      final (router, first) = await openAtHome(tester);
      _push(router, name);
      await settleBrowser(tester);
      final readings = [_reading(router, first)];

      router.pop();
      await settleBrowser(tester);
      readings.add(_reading(router, first));

      expect(readings, [shown, '(0, /, Home)']);
    });
  }

  testWidgets('Push the tabs page, pick tab Two, push Detail, remove the '
      'tabs page: back from Detail shows Home', (tester) async {
    final (router, first) = await openAtHome(tester);
    _push(router, 'TabsRoute');
    await settleBrowser(tester);
    router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
    await settleBrowser(tester);
    _push(router, 'DetailRoute');
    await settleBrowser(tester);
    final readings = [_reading(router, first)];

    _removeTabsPage(router);
    await settleBrowser(tester);
    readings.add(_reading(router, first));
    await pressBrowserBack(tester);
    readings.add(_reading(router, first));

    expect(readings, [
      '(3, /detail, Home Tabs Detail)',
      '(1, /detail, Home Detail)',
      '(0, /, Home)',
    ]);
  });
}
