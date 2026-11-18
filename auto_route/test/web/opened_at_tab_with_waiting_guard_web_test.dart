// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// In a real browser, an app opened at a link to a tab whose guard waits
// keeps the one entry the browser made for the link, with prefix matches
// too (callmephil/auto_route_library#20). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/opened_at_tab_with_waiting_guard_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where the browser makes one entry for a url it opens, and a back or
// forward traversal moves to another entry and adds none.

// A guard that answers only when the test tells it to, as in the report.
class _SlowGuard extends AutoRouteGuard {
  final pending = <NavigationResolver>[];

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) =>
      pending.add(resolver);
}

late _SlowGuard _guard;

NamedRouteDef _page(String name, String path, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: Text(name)),
);

// The routes of the report: Home at '/', and the tabs page at '/tabs' with
// the tabs One and Two, whose guard waits. And Detail, for the push.
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
      children: [
        _page('OneRoute', 'one'),
        _page('TwoRoute', 'two', guard: _guard),
      ],
    ),
    _page('DetailRoute', '/detail'),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  setUp(() => _guard = _SlowGuard());

  // Opens the app at [link] the way a browser does, with prefix matches,
  // and returns its router with a reading of the page on top, the entry
  // counted from the link's and the url.
  Future<(RootStackRouter, String Function())> open(
    WidgetTester tester,
    String link,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    final first = browserSerialCount < 0 ? 0 : browserSerialCount;
    String reading() =>
        '${router.topRoute.name} ${browserSerialCount - first} $browserPath';
    openBrowserAt(tester, link);
    await pumpAsRunApp(
      tester,
      MaterialApp.router(
        routerConfig: router.config(includePrefixMatches: true),
      ),
    );
    await settleBrowser(tester);
    return (router, reading);
  }

  // Pushes Detail on [router], then presses the browser's back button and
  // its forward button: the [reading] after each step.
  Future<List<String>> pushDetailThenWalk(
    WidgetTester tester,
    RootStackRouter router,
    String Function() reading,
  ) async {
    unawaited(router.push<Object?>(const NamedRoute('DetailRoute')));
    await settleBrowser(tester);
    final readings = [reading()];
    await pressBrowserBack(tester);
    readings.add(reading());
    await pressBrowserForward(tester);
    readings.add(reading());
    return readings;
  }

  testWidgets('Opened at /tabs/two, the guard of tab Two says yes: one entry '
      'for the link', (tester) async {
    final (router, reading) = await open(tester, '/tabs/two');
    final readings = [reading()];
    // The guard was asked once, and holds its answer.
    expect(_guard.pending, hasLength(1));
    _guard.pending.singleOrNull?.next();
    await settleBrowser(tester);
    readings.add(reading());

    expect(readings, ['OneRoute 0 /tabs/one', 'TwoRoute 0 /tabs/two']);
    expect(await pushDetailThenWalk(tester, router, reading), [
      'DetailRoute 1 /detail',
      'TwoRoute 0 /tabs/two',
      'DetailRoute 1 /detail',
    ]);
  });

  testWidgets('Opened at /tabs/two, the guard of tab Two says no: one entry '
      'for the link, which shows Home', (tester) async {
    final (router, reading) = await open(tester, '/tabs/two');
    final readings = [reading()];
    expect(_guard.pending, hasLength(1));
    _guard.pending.singleOrNull?.reject();
    await settleBrowser(tester);
    readings.add(reading());

    expect(readings, ['OneRoute 0 /tabs/one', 'HomeRoute 0 /']);
    expect(await pushDetailThenWalk(tester, router, reading), [
      'DetailRoute 1 /detail',
      'HomeRoute 0 /',
      'DetailRoute 1 /detail',
    ]);
  });

  testWidgets('Opened at /tabs, which names no tab: one entry for the link, '
      'with tab One', (tester) async {
    final (router, reading) = await open(tester, '/tabs');

    expect(reading(), 'OneRoute 0 /tabs/one');
    expect(await pushDetailThenWalk(tester, router, reading), [
      'DetailRoute 1 /detail',
      'OneRoute 0 /tabs/one',
      'DetailRoute 1 /detail',
    ]);
  });
}
