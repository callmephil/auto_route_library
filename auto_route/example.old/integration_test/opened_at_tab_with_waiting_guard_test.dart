import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, an app opened at a link to a tab whose guard waits keeps the
// one browser entry the browser made for the link, with prefix matches too.
// Before, the url of the tab the tabs show while the guard decides did not
// count as the link's, so Home, which the prefix match opens under the
// tabs, got an entry of its own, and back from the tab showed Home
// (callmephil/auto_route_library#20).
// Headless tests: auto_route/test/opened_at_tab_with_waiting_guard_test.dart
// and auto_route/test/web/opened_at_tab_with_waiting_guard_web_test.dart.
//
// Native behavior this holds to: the HTML standard's session history,
// where the browser makes one entry for a url it opens, and a back or
// forward traversal moves to another entry and adds none. Web only: off
// the web there is no browser history.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('opened at a tab whose guard waits', () {
    // Opens the app at [link] with prefix matches, and returns a reading of
    // the browser entry counted from the link's, the url and the page on
    // top.
    Future<String Function()> open(
      WidgetTester tester,
      RootStackRouter router,
      String link,
    ) async {
      final linkEntry = browserEntryIndex() ?? 0;
      // The config reads the platform's initial route when it is first
      // made, so it is made inside the app, after pumpAppAtDeepLink sets
      // the link, as runApp would find it.
      await pumpAppAtDeepLink(
        tester,
        link,
        Builder(
          builder: (_) => MaterialApp.router(
            routerConfig: router.config(includePrefixMatches: true),
          ),
        ),
      );
      await SystemNavigator.selectMultiEntryHistory();
      return () =>
          '(${(browserEntryIndex() ?? 0) - linkEntry}, ${browserUrl()}, '
          '${router.topRoute.name})';
    }

    // Pushes Detail, then presses the browser's back button, which shows
    // [linkPage] at [linkUrl], and its forward button, which shows Detail.
    Future<void> pushDetailThenWalk(
      WidgetTester tester,
      RootStackRouter router, {
      required String linkPage,
      required String linkUrl,
    }) async {
      await expectBrowserEntryAfter(1, () async {
        unawaited(router.push<Object?>(const NamedRoute('DetailRoute')));
        await tester.pumpAndSettle();
      });
      await expectBrowserUrl('/detail');
      await expectBrowserBackWalk(tester, router, [(linkPage, linkUrl)]);
      await expectBrowserEntryAfter(1, pressBrowserForward);
      await tester.pumpAndSettle();
      await expectBrowserUrl('/detail');
      expect(router.topRoute.name, 'DetailRoute', reason: 'after forward');
    }

    // Steps: with prefix matches, open the app at the url of tab Two. The
    // guard of tab Two holds its answer, then says yes. Push Detail, press
    // the browser's back button, then its forward button.
    // Was: two entries while the guard decided, the url of Home and then
    // the url of tab One. Back from tab Two showed Home.
    // Should: one entry, with the url of tab One, then the url of tab Two.
    // The push adds one, and back and forward walk between the two.
    testWidgets(
      'The guard says yes: one entry for the link',
      (tester) async {
        final pending = <NavigationResolver>[];
        final router = _router(pending);
        final reading = await open(tester, router, '/tabs/two');
        final readings = [reading()];

        // The guard was asked once, and holds its answer.
        expect(pending, hasLength(1));
        pending.singleOrNull?.next();
        await tester.pumpAndSettle();
        await expectBrowserUrl('/tabs/two');
        readings.add(reading());
        expect(readings, [
          '(0, /tabs/one, OneRoute)',
          '(0, /tabs/two, TwoRoute)',
        ]);

        await pushDetailThenWalk(
          tester,
          router,
          linkPage: 'TwoRoute',
          linkUrl: '/tabs/two',
        );
      },
      skip: !kIsWeb,
    );

    // Steps: as above, but the guard says no, which takes the tabs page
    // back and leaves Home.
    // Was: both entries held the url of Home, and back showed Home again.
    // Should: one entry, with the url of Home.
    testWidgets(
      'The guard says no: one entry for the link, which shows Home',
      (tester) async {
        final pending = <NavigationResolver>[];
        final router = _router(pending);
        final reading = await open(tester, router, '/tabs/two');
        final readings = [reading()];

        expect(pending, hasLength(1));
        pending.singleOrNull?.reject();
        await tester.pumpAndSettle();
        await expectBrowserUrl('/');
        readings.add(reading());
        expect(readings, ['(0, /tabs/one, OneRoute)', '(0, /, HomeRoute)']);

        await pushDetailThenWalk(
          tester,
          router,
          linkPage: 'HomeRoute',
          linkUrl: '/',
        );
      },
      skip: !kIsWeb,
    );

    // Steps: with prefix matches, open the app at the url of the tabs page.
    // That url names no tab, so the tabs show tab One. Push Detail, then
    // press the browser's back button and its forward button.
    // Was: two entries, the url of Home and then the url of tab One.
    // Should: one entry, with the url of tab One.
    testWidgets(
      'A link that names no tab: one entry for the link',
      (tester) async {
        final router = _router([]);
        final reading = await open(tester, router, '/tabs');
        expect(reading(), '(0, /tabs/one, OneRoute)');

        await pushDetailThenWalk(
          tester,
          router,
          linkPage: 'OneRoute',
          linkUrl: '/tabs/one',
        );
      },
      skip: !kIsWeb,
    );
  });
}

NamedRouteDef _page(String name, String path, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: Text(name)),
);

// The routes of the report: Home at '/', and the tabs page at '/tabs' with
// the tabs One and Two. The guard of Two answers only when the test tells it
// to, as in the report: it keeps the resolver of each ask in [pending]. And
// Detail, for the push.
RootStackRouter _router(List<NavigationResolver> pending) => .build(
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
        _page(
          'TwoRoute',
          'two',
          guard: AutoRouteGuard.simple((resolver, _) => pending.add(resolver)),
        ),
      ],
    ),
    _page('DetailRoute', '/detail'),
  ],
);
