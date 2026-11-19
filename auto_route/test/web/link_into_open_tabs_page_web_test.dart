@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, a url typed into the address bar that names another
// tab of the tabs page on screen keeps the entry the browser made for it,
// and the app moves the browser nowhere
// (callmephil/auto_route_library#35). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/link_into_open_tabs_page_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where a navigation to a new url adds one entry, and the browser moves
// between entries only by a traversal the user or the page asks for.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, then Tabs with the tabs One and Two, each with a nested router: One
// with OneIndex and Z1, Two with TwoIndex.
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
          children: [_page('OneIndexRoute', ''), _page('Z1Route', 'z')],
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

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('The url /tabs/one/z typed on tab Two keeps the entry the '
      'browser made for it, and back and forward walk Two, One and Home', (
    tester,
  ) async {
    final router = _tabsRouter();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
    await settleBrowser(tester);
    router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
    await settleBrowser(tester);
    String shown() =>
        '${router.topRoute.name} $browserPath ${browserSerialCount - home}';

    // The browser's popstate events while the app opens the url: one, for
    // the entry the browser made, and none of a step of the app's own.
    final landedOn = <String>[];
    final landings = window.onPopState.listen((_) => landedOn.add(browserPath));
    addTearDown(landings.cancel);
    await browserMove(tester, () => window.location.hash = '/tabs/one/z');
    await settleBrowser(tester);
    expect(shown(), 'Z1Route /tabs/one/z 3');
    expect(landedOn, ['/tabs/one/z']);

    final backWalk = <String>[];
    for (var i = 0; i < 4 && browserSerialCount > home; i++) {
      await pressBrowserBack(tester);
      backWalk.add(shown());
    }
    expect(backWalk, [
      'TwoIndexRoute /tabs/two 2',
      'OneIndexRoute /tabs/one 1',
      'HomeRoute / 0',
    ]);
    final forwardWalk = <String>[];
    for (var i = 0; i < 3; i++) {
      await pressBrowserForward(tester);
      forwardWalk.add(shown());
    }
    expect(forwardWalk, [
      'OneIndexRoute /tabs/one 1',
      'TwoIndexRoute /tabs/two 2',
      'Z1Route /tabs/one/z 3',
    ]);
  });
}
