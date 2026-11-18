import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, the browser's back button after pushAll in a tab not on
// screen shows each page once. Before, the press onto the entry of the
// first page of that tab took the url of the tab on screen for a new entry
// and moved the browser forward: 6 presses, and the entries ahead were lost
// (callmephil/auto_route_library#21).
// Headless tests:
// auto_route/test/back_after_push_all_in_hidden_tab_test.dart and
// auto_route/test/web/back_after_push_all_in_hidden_tab_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.pop in the router of
// the tab closes Y1, then X1. In the HTML standard's session history, a
// back or forward traversal moves to another entry and adds none. Web only:
// off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after pushAll in a tab not on screen', () {
    // Steps: on Home, open Tabs on tab One. Select tab Two. Call pushAll of
    // X1 and Y1 on the router of tab One, then select tab One. Press the
    // browser's back button until Home, then its forward button until Y1.
    // Was: 6 back presses; the third moved the browser forward.
    // Should: back shows X1, Two, OneIndex, then Home, one entry each, and
    // forward walks the same entries up to Y1.
    testWidgets(
      'Back shows X1, Two, OneIndex, then Home',
      (tester) async {
        final router = _tabsRouter();
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex()!;

        unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        unawaited(
          tabs.innerRouterOf<StackRouter>('OneRoute')!.pushAll(const [
            NamedRoute<Object?>('X1Route'),
            NamedRoute<Object?>('Y1Route'),
          ]),
        );
        await tester.pumpAndSettle();
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 4);
        await expectBrowserUrl('/tabs/one/y');

        await expectBrowserBackWalk(tester, router, [
          ('X1Route', '/tabs/one/x'),
          ('TwoIndexRoute', '/tabs/two'),
          ('OneIndexRoute', '/tabs/one'),
          ('HomeRoute', '/'),
        ]);

        for (final (step, (name, url)) in [
          ('OneIndexRoute', '/tabs/one'),
          ('TwoIndexRoute', '/tabs/two'),
          ('X1Route', '/tabs/one/x'),
          ('Y1Route', '/tabs/one/y'),
        ].indexed) {
          pressBrowserForward();
          await expectBrowserEntry(home + step + 1);
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(router.topRoute.name, name, reason: 'after forward to $url');
        }
      },
      skip: !kIsWeb,
    );
  });
}

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
