import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A link to a guarded tab whose guard answers after the tabs are gone
// leaves the next page's history entry alone.
// Setup: a start page, then a page with the tabs FeedTab and ProfileTab
// (ProfileTab's guard takes its time), then SettingsRoute and DetailRoute.
// Steps: open the link '/home/profile'. FeedTab shows while the guard
// decides. Replace HomeRoute with SettingsRoute. The guard then lets
// ProfileTab in. Push DetailRoute, then go back.
// Was: StartRoute showed. The guard's answer marked the url for replace
// though the tabs were gone, so DetailRoute's entry took SettingsRoute's
// place in the history, and back skipped SettingsRoute.
// Should: back shows SettingsRoute.
// Native behavior this holds to: back goes through every screen the user
// was shown and left with a push, on Android's back stack, iOS's
// UINavigationController and the browser's history. A navigation that
// shows nothing, here to a tab no longer on screen, writes no entry.
// On the web router.back() is the browser's own history.back(), which the
// default test runner never hands to the app, so this test runs off the web.
// The browser's back button is tested in
// test/web/late_tab_guard_browser_back_web_test.dart.
void main() {
  testWidgets('back after a late tab guard shows the page pushed over', (
    tester,
  ) async {
    final decision = Completer<bool>();
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'StartRoute',
          path: '/',
          builder: (_, _) => const Center(child: Text('StartRoute')),
        ),
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/home',
          builder: (_, _) => const AutoTabsRouter(
            routes: [NamedRoute('FeedTab'), NamedRoute('ProfileTab')],
          ),
          children: [
            NamedRouteDef(
              name: 'FeedTab',
              path: 'feed',
              builder: (_, _) => const Center(child: Text('FeedTab')),
            ),
            NamedRouteDef(
              name: 'ProfileTab',
              path: 'profile',
              guards: [
                AutoRouteGuard.simple((resolver, _) async {
                  if (await decision.future) resolver.next();
                }),
              ],
              builder: (_, _) => const Center(child: Text('ProfileTab')),
            ),
          ],
        ),
        for (final (name, path) in [
          ('SettingsRoute', '/settings'),
          ('DetailRoute', '/detail'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => Center(child: Text(name)),
          ),
      ],
    );
    await pumpRouterApp(tester, router);
    unawaited(router.navigatePath('/home/profile'));
    await tester.pumpAndSettle();
    expect(find.text('FeedTab'), findsOneWidget);
    unawaited(router.replace(const NamedRoute('SettingsRoute')));
    await tester.pumpAndSettle();
    decision.complete(true);
    await tester.pumpAndSettle();

    expect(router.navigationHistory.isUrlStateMarkedForReplace, isFalse);
    unawaited(router.push(const NamedRoute('DetailRoute')));
    await tester.pumpAndSettle();
    router.back();
    await tester.pumpAndSettle();

    expect(find.text('SettingsRoute'), findsOneWidget);
    expect(router.urlState.url, '/settings');
  }, skip: kIsWeb);
}
