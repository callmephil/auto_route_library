@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, after the app closes pages in a tab not on screen,
// each press of the back button shows another page
// (callmephil/auto_route_library#39). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/back_after_remove_until_in_hidden_tab_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where back closes the
// page on top and a removed page never comes back. In the HTML standard's
// session history, back and forward move to another entry and add or
// change none.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Tabs with the tabs One and Two, each with a nested router: One
// with OneIndex, X1 and Y1, Two with TwoIndex.
RootStackRouter _tabsRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [
          NamedRoute<Object?>('OneRoute'),
          NamedRoute<Object?>('TwoRoute'),
        ],
        builder: (_, child) => child,
      ),
      children: [
        NamedRouteDef(
          name: 'OneRoute',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OneIndexRoute', ''),
            _page('X1Route', 'x'),
            _page('Y1Route', 'y'),
          ],
        ),
        NamedRouteDef(
          name: 'TwoRoute',
          path: 'two',
          builder: (_, _) => const AutoRouter(),
          children: [_page('TwoIndexRoute', '')],
        ),
      ],
    ),
  ],
);

// Runs [step] and returns by how many entries it changed the length of the
// browser's history: a push drops the entries ahead and adds one, and a
// move through the history changes none.
Future<int> _historyLengthChangeOf(Future<void> Function() step) async {
  final before = browserEntryCount;
  await step();
  return browserEntryCount - before;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('After removeUntil in a tab not on screen, back shows '
      'OneIndex, then Home, and forward walks back to Two', (tester) async {
    final router = _tabsRouter();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await settleBrowser(tester);
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
      ..setActiveIndex(1);
    await settleBrowser(tester);
    final one = tabs.innerRouterOf<StackRouter>('OneRoute')!;
    unawaited(
      one.pushAll(const [
        NamedRoute<Object?>('X1Route'),
        NamedRoute<Object?>('Y1Route'),
      ]),
    );
    await settleBrowser(tester);
    tabs.setActiveIndex(0);
    await settleBrowser(tester);
    tabs.setActiveIndex(1);
    await settleBrowser(tester);
    String shown() =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';
    expect(shown(), 'TwoIndexRoute /tabs/two 5');

    // The browser stands on its last entry, so the entries the closing
    // drops come off the length of its history.
    final closingChange = await _historyLengthChangeOf(() async {
      one.removeUntil((route) => route.name == 'OneIndexRoute');
      await settleBrowser(tester);
    });

    // One entry for Two, with none ahead: the entries of X1, Y1 and the
    // first of Two are gone.
    expect((shown(), closingChange), ('TwoIndexRoute /tabs/two 2', -3));

    final backWalk = <String>[];
    final forwardWalk = <String>[];
    final walkChange = await _historyLengthChangeOf(() async {
      // At most 3 presses: before the fix, the walk took 3.
      for (var i = 0; i < 3 && browserSerialCount > home; i++) {
        await pressBrowserBack(tester);
        backWalk.add(shown());
      }
      for (var i = 0; i < 2; i++) {
        await pressBrowserForward(tester);
        forwardWalk.add(shown());
      }
    });
    expect(backWalk, ['OneIndexRoute /tabs/one 1', 'HomeRoute / 0']);
    expect(forwardWalk, [
      'OneIndexRoute /tabs/one 1',
      'TwoIndexRoute /tabs/two 2',
    ]);
    // Back and forward added no entry and dropped none.
    expect(walkChange, 0);
  });
}
