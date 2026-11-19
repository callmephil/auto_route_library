import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, the pages of a nested router leave the browser's way back
// with the page that holds the router, as a tabs page or a shell, when the
// app closes that page. Before, the history took them for open pages while
// the closed page's widget was still there. After a removal the browser
// kept their entries, and back opened the closed page again. A pop wrote
// the url of the page under as a new entry
// (callmephil/auto_route_library#40).
// Headless tests:
// auto_route/test/back_after_closing_nested_router_page_test.dart and
// auto_route/test/web/back_after_closing_nested_router_page_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where pop and
// removeRoute take the route out with the navigator nested in it, and the
// system back then shows the route under it. The HTML standard's session
// history can't drop an entry, so the page under takes the entry of the
// closed page, or the browser steps back to the entry of that page. Web
// only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after the app closes a page with a nested router', () {
    // Steps: with prefix matches, open the app at the url of tab Two. The
    // link opens Home under the tabs page. Push Detail, remove the tabs
    // page, then press the browser's back button.
    // Was: the browser kept the entry of tab Two, and back opened the tabs
    // page again over Detail.
    // Should: Home takes the link's entry, and back shows Home at '/'.
    testWidgets(
      "Remove the tabs page under Detail: Home takes the link's entry",
      (tester) async {
        final router = _router();
        final linkEntry = browserEntryIndex() ?? 0;
        // The config reads the platform's initial route when it is first
        // made, so it is made inside the app, after pumpAppAtDeepLink sets
        // the link, as runApp would find it.
        await pumpAppAtDeepLink(
          tester,
          '/tabs/two',
          Builder(
            builder: (_) => MaterialApp.router(
              routerConfig: router.config(includePrefixMatches: true),
            ),
          ),
        );
        await SystemNavigator.selectMultiEntryHistory();
        await expectBrowserEntryAfter(1, () async {
          unawaited(router.push<Object?>(const NamedRoute('DetailRoute')));
          await tester.pumpAndSettle();
        });

        router.removeWhere((route) => route.name == 'TabsRoute');
        await tester.pumpAndSettle();
        await SystemNavigator.selectMultiEntryHistory();
        await expectBrowserEntry(linkEntry + 1);
        await expectBrowserUrl('/detail');
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'DetailRoute',
        ]);

        await expectBrowserBackWalk(tester, router, [('HomeRoute', '/')]);
        expect(router.stack.map((page) => page.name), ['HomeRoute']);
      },
      skip: !kIsWeb,
    );

    // Steps: push the tabs page, or a shell, over Home, then pop it.
    // Was: the pop wrote the url of Home as a new entry after the entry of
    // the closed page, and back opened the closed page again.
    // Should: the browser steps back to the entry of Home.
    for (final name in ['TabsRoute', 'ShellRoute']) {
      testWidgets(
        'Pop $name: the browser steps back to the entry of Home',
        (tester) async {
          final router = _router();
          await pumpRouterAppWithConfig(tester, router);
          final home = browserEntryIndex()!;
          await expectBrowserEntryAfter(1, () async {
            unawaited(router.push<Object?>(NamedRoute(name)));
            await tester.pumpAndSettle();
          });

          router.pop();
          await tester.pumpAndSettle();
          await expectBrowserEntry(home);
          await expectBrowserUrl('/');
          expect(router.topRoute.name, 'HomeRoute');
        },
        skip: !kIsWeb,
      );
    }
  });
}

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
