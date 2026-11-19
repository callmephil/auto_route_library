import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, after the app closes pages in a tab not on screen, each press
// of the browser's back button shows another page. Before, the entries of
// the closed pages left and put two entries of the tab on screen side by
// side, so one back press showed that tab again
// (callmephil/auto_route_library#39).
// Headless tests:
// auto_route/test/back_after_remove_until_in_hidden_tab_test.dart and
// auto_route/test/web/back_after_remove_until_in_hidden_tab_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where back closes the
// page on top and a removed page never comes back. In the HTML standard's
// session history, back and forward move to another entry and add or
// change none. Web only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after removeUntil in a tab not on screen', () {
    // Steps: on Home, open Tabs on tab One. Select tab Two. Call pushAll of
    // X1 and Y1 on the router of tab One, select tab One, then tab Two
    // again. Call removeUntil on the router of tab One until OneIndex.
    // Press the browser's back button until Home, then its forward button
    // until Two.
    // Was: the browser held two entries of Two in a row, and the first back
    // press showed Two again.
    // Should: one entry for Two; back shows OneIndex, then Home, and
    // forward walks the same entries up to Two.
    testWidgets(
      'Back shows OneIndex, then Home',
      (tester) async {
        final router = _tabsRouter();
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex()!;

        unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        final one = tabs.innerRouterOf<StackRouter>('OneRoute')!;
        unawaited(
          one.pushAll(const [
            NamedRoute<Object?>('X1Route'),
            NamedRoute<Object?>('Y1Route'),
          ]),
        );
        await tester.pumpAndSettle();
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();
        tabs.setActiveIndex(1);
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 5);
        await expectBrowserUrl('/tabs/two');

        one.removeUntil((route) => route.name == 'OneIndexRoute');
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 2);
        await expectBrowserUrl('/tabs/two');

        await expectBrowserBackWalk(tester, router, [
          ('OneIndexRoute', '/tabs/one'),
          ('HomeRoute', '/'),
        ]);

        for (final (step, (name, url)) in [
          ('OneIndexRoute', '/tabs/one'),
          ('TwoIndexRoute', '/tabs/two'),
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
