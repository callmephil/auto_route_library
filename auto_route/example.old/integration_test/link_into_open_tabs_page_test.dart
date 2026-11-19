import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, a url typed into the address bar that names another tab of
// the tabs page on screen keeps the entry the browser made for it, and the
// app moves the browser nowhere. Before, the tabs page that the link opens
// again reported the url of the tab on screen first, so the app stepped the
// browser back from the link's entry and wrote the link's url again as a
// new entry (callmephil/auto_route_library#35).
// Headless tests: auto_route/test/link_into_open_tabs_page_test.dart and
// auto_route/test/web/link_into_open_tabs_page_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where a navigation to a new url adds one entry, and the browser moves
// between entries only by a traversal the user or the page asks for. Off
// the web, the platform's link adds one step back, as each call of
// Android's NavController.navigate pushes one destination.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a link into another tab of the tabs page on screen', () {
    // Steps: on Home, open Tabs on tab One, then select tab Two. Type the url
    // /tabs/one/z on the web, or hand the app that link off the web. Go
    // back until Home.
    // Was: on the web, the browser stepped back from the entry it made for
    // the url, and the app wrote the url again as a new entry.
    // Should: the platform reports the one url, Z1 shows on the entry the
    // browser made, and back shows Two, One, then Home.
    testWidgets(
      'keeps one entry for the link, and back shows Two, One and Home',
      (tester) async {
        final router = _tabsRouter();
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex();
        unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
        await tester.pumpAndSettle();
        router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/tabs/two');
        // The urls the platform hands the app from now on, as the browser
        // reports each entry it lands on.
        final provider = router.routeInfoProvider();
        final reported = <String>[];
        void onReport() => reported.add(provider.value.uri.toString());
        provider.addListener(onReport);
        addTearDown(() => provider.removeListener(onReport));

        if (kIsWeb) {
          typeBrowserUrl('/tabs/one/z');
        } else {
          await tester.binding.handlePushRoute('/tabs/one/z');
        }
        await pumpUntilFound(tester, find.text('Z1Route'));
        // A step of the app's own would have landed by now.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await expectBrowserUrl('/tabs/one/z');
        if (home != null) await expectBrowserEntry(home + 3);
        expect(router.topRoute.name, 'Z1Route');
        expect(reported, ['/tabs/one/z']);

        const wayBack = [
          ('TwoIndexRoute', '/tabs/two'),
          ('OneIndexRoute', '/tabs/one'),
          ('HomeRoute', '/'),
        ];
        if (kIsWeb) {
          await expectBrowserBackWalk(tester, router, wayBack);
          return;
        }
        for (final (name, url) in wayBack) {
          router.back();
          await tester.pumpAndSettle();
          expect((router.topRoute.name, router.currentUrl), (name, url));
        }
      },
    );
  });
}

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
