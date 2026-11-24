@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, pushAndPopUntil into a tabs page that shows another
// tab leaves no entry of the old tab ahead
// (callmephil/auto_route_library#47). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/push_and_pop_until_into_tabs_page_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.pushAndRemoveUntil,
// where the removed routes do not come back. In the HTML standard,
// history.pushState adds the entry of a navigation and drops the entries
// ahead, and only back and forward keep them.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, the tabs page of the issue with the tabs One and Two, and A.
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
    _page('ARoute', '/a'),
  ],
);

// Runs [step] and returns by how many entries it changed the length of the
// browser's history: a push drops the entries ahead and adds one, and a
// move through the history changes none.
Future<int> _historyLengthChangeOf(Future<void> Function() step) async {
  final before = window.history.length;
  await step();
  return window.history.length - before;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Opens Tabs on tab Two over Home; shown() reads page, url and entry.
  Future<(RootStackRouter, String Function())> openOnTwo(
    WidgetTester tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await settleBrowser(tester);
    router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
    await settleBrowser(tester);
    return (
      router,
      () => '${router.topRoute.name} $browserPath ${browserSerialCount - home}',
    );
  }

  testWidgets('pushAndPopUntil of Tabs on tab One until Home, from tab Two: '
      'no entry is ahead, and back shows Home', (tester) async {
    final (router, shown) = await openOnTwo(tester);
    expect(shown(), 'TwoRoute /tabs/two 2');

    // The browser stands on its last entry, so the entries the call drops
    // come off the length of its history.
    final change = await _historyLengthChangeOf(() async {
      unawaited(
        router.pushAndPopUntil(
          const NamedRoute<Object?>(
            'TabsRoute',
            children: [NamedRoute('OneRoute')],
          ),
          predicate: (route) => route.settings.name == 'HomeRoute',
        ),
      );
      await settleBrowser(tester);
    });

    // A new entry for tab One, and the old entries of One and Two are gone.
    expect((shown(), change), ('OneRoute /tabs/one 1', -1));
    await pressBrowserBack(tester);
    expect(shown(), 'HomeRoute / 0');
  });

  // Steps: on tab Two, push A, press back two times, onto tab One, then
  // select tab Two.
  testWidgets('A tab change after back presses drops the entry of the page '
      'that back closed', (tester) async {
    final (router, shown) = await openOnTwo(tester);
    unawaited(router.push(const NamedRoute<Object?>('ARoute')));
    await settleBrowser(tester);
    await pressBrowserBack(tester);
    await pressBrowserBack(tester);
    expect(shown(), 'OneRoute /tabs/one 1');

    final change = await _historyLengthChangeOf(() async {
      router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
      await settleBrowser(tester);
    });

    // A new entry for tab Two, and the entries of Two and A ahead are gone.
    expect((shown(), change), ('TwoRoute /tabs/two 2', -1));
  });
}
