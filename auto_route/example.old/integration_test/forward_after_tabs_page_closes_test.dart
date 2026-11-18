import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, the browser's forward button walks the same entries that its
// back button walked down, also after the back button closed a tabs page.
// Before, the second forward press showed Z1 over OneIndex on a fourth
// entry: the nested router of tab One, built off the screen, and then the
// change to tab One reported urls before Z1 was on, and the web history took
// each for a navigation (callmephil/auto_route_library#22).
// Headless tests:
// auto_route/test/forward_after_tabs_page_closes_test.dart and
// auto_route/test/web/forward_after_tabs_page_closes_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// a forward traversal moves to a later entry and changes none. The forward
// walk is web only: off the web there is no browser forward button. Off the
// web, the same cause gave a link into a page of another tab two entries in
// the app's own history; the second test holds it to one, as one navigation
// is one step back on Android's back stack and in Flutter's Navigator.
// Headless test: auto_route/test/link_into_page_of_other_tab_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('forward after the tabs page closes', () {
    // Steps: on Home, open Tabs on tab One. In One, call pushAll with X1 and
    // Y1. Select tab Two, then tab One. In One, call replaceAll with Z1.
    // Press the browser's back button two times, then its forward button two
    // times.
    // Was: the second forward press showed Z1 on a fourth entry, and the
    // third entry held /tabs/one.
    // Should: forward shows Two and then Z1 on the third entry, which is
    // /tabs/one/z. Back and forward again walk the same entries.
    testWidgets(
      'Forward shows Two, then Z1 on its entry',
      (tester) async {
        final router = _tabsRouter();
        await pumpRouterConfigApp(tester, router.config());
        final home = browserEntryIndex()!;

        unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
        final one = tabs.innerRouterOf<StackRouter>('OneTab')!;
        unawaited(
          one.pushAll(const [
            NamedRoute<Object?>('X1Route'),
            NamedRoute<Object?>('Y1Route'),
          ]),
        );
        await tester.pumpAndSettle();
        tabs.setActiveIndex(1);
        await tester.pumpAndSettle();
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();
        unawaited(one.replaceAll(const [NamedRoute<Object?>('Z1Route')]));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 2);
        await expectBrowserUrl('/tabs/one/z');

        await expectBrowserBackWalk(tester, router, [
          ('TwoIndexRoute', '/tabs/two'),
          ('HomeRoute', '/'),
        ]);
        for (final (name, url) in [
          ('TwoIndexRoute', '/tabs/two'),
          ('Z1Route', '/tabs/one/z'),
        ]) {
          await expectBrowserEntryAfter(1, pressBrowserForward);
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(router.topRoute.name, name, reason: 'after forward to $url');
        }
        await expectBrowserEntry(home + 2);

        // The entries stay the walk's: back and forward again.
        await expectBrowserBackWalk(tester, router, [
          ('TwoIndexRoute', '/tabs/two'),
        ]);
        await expectBrowserEntryAfter(1, pressBrowserForward);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/tabs/one/z');
        expect(router.topRoute.name, 'Z1Route');
      },
      skip: !kIsWeb,
    );

    // Steps: on Home, open Tabs on tab One, then select Two and One again.
    // The platform hands the app /tabs/two/detail. Call back() until the
    // history has no step back.
    // Was: the page TwoIndex showed for no frame and got an entry of its own.
    // So back() went from TwoDetail to TwoIndex.
    // Should: back() goes from TwoDetail to One, the page shown before.
    testWidgets(
      'Off the web, a link into a page of another tab adds one entry',
      (tester) async {
        final router = _twoTabsRouter();
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute<Object?>('Tabs')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('Tabs')!;
        for (final index in [1, 0]) {
          tabs.setActiveIndex(index);
          await tester.pumpAndSettle();
        }

        await tester.binding.handlePushRoute('/tabs/two/detail');
        await tester.pumpAndSettle();

        expect(router.topRoute.name, 'TwoDetail');
        final urls = [router.currentUrl];
        for (
          var i = 0;
          i < 8 && router.navigationHistory.canNavigateBack;
          i++
        ) {
          router.back();
          await tester.pumpAndSettle();
          urls.add(router.currentUrl);
        }
        expect(urls, [
          '/tabs/two/detail',
          '/tabs/one',
          '/tabs/two',
          '/tabs/one',
          '/',
        ]);
      },
      skip: kIsWeb,
    );
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _tabsRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [
          NamedRoute<Object?>('OneTab'),
          NamedRoute<Object?>('TwoTab'),
        ],
        builder: (_, child) => child,
      ),
      children: [
        NamedRouteDef(
          name: 'OneTab',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OneIndexRoute', ''),
            _page('X1Route', 'x'),
            _page('Y1Route', 'y'),
            _page('Z1Route', 'z'),
          ],
        ),
        NamedRouteDef(
          name: 'TwoTab',
          path: 'two',
          builder: (_, _) => const AutoRouter(),
          children: [_page('TwoIndexRoute', '')],
        ),
      ],
    ),
  ],
);

// Home, then Tabs with the tabs One and Two; each tab holds a nested router
// with an Index page and a Detail page.
NamedRouteDef _tab(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => const AutoRouter(),
  children: [_page('${name}Index', ''), _page('${name}Detail', 'detail')],
);

RootStackRouter _twoTabsRouter() => .build(
  routes: [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Tabs',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute<Object?>('One'), NamedRoute<Object?>('Two')],
        ),
      ),
      children: [_tab('One', 'one'), _tab('Two', 'two')],
    ),
  ],
);
