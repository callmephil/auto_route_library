@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// A link to a guarded tab whose guard answers after the tabs are gone leaves
// the next page's browser entry alone.
// Setup: a start page, then a page with the tabs FeedTab and ProfileTab
// (ProfileTab's guard takes its time), then SettingsRoute and DetailRoute,
// in a browser.
// Steps: open the link '/home/profile'. FeedTab shows while the guard
// decides. Replace HomeRoute with SettingsRoute. The guard then lets
// ProfileTab in. Push DetailRoute, then press the browser's back button.
// Was: the guard's answer marked the url for replace though the tabs were
// gone, so DetailRoute's url took the place of SettingsRoute's entry, and
// the back button skipped SettingsRoute.
// Should: back shows SettingsRoute at '/settings'.
// Native behavior this holds to: the browser's back button goes to the entry
// of the page the user left with a push. A navigation that shows nothing,
// here to a tab no longer on screen, writes no entry.
// Headless test off the web:
// test/nested_tabs_router/guarded_tab_link_after_tabs_left_test.dart
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('The browser back button after a late tab guard shows the page '
      'pushed over', (tester) async {
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
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.navigatePath('/home/profile'));
    await settleBrowser(tester);
    expect(find.text('FeedTab'), findsOneWidget);
    unawaited(router.replace(const NamedRoute('SettingsRoute')));
    await settleBrowser(tester);
    decision.complete(true);
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('DetailRoute')));
    await settleBrowser(tester);
    expect(browserPath, '/detail');

    await pressBrowserBack(tester);

    expect(find.text('SettingsRoute'), findsOneWidget);
    expect(browserPath, '/settings');
    expect(router.urlState.url, '/settings');
  });
}
