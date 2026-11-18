import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, a link to another tab of the tabs page on screen adds one
// entry to the app's history, so back() walks the tabs the user saw, the
// latest first.
// Headless test: auto_route/test/back_after_link_to_other_tab_test.dart.
//
// Native behavior this holds to: a link is one navigation, and one
// navigation adds one step back: each NavController.navigate() pushes one
// destination and back pops the top one (developer.android.com/guide/
// navigation/backstack); Flutter's Navigator.push puts one route on and pop
// takes the top-most off (navigator.dart 5023 and 5607, Flutter 3.50.0).
// Off the web only: on the web, back() is the browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back() after a link to another tab, off the web', () {
    // Steps: Home, then the tabs page on Feed; the user picks Mail, then
    // Settings; the platform hands the app the link /tabs/feed; back()
    // until the history can't.
    // Was: the link added three entries, and back() showed Settings, Feed
    // and Settings again before Mail.
    // Should: Feed, Settings, Mail, Feed, Home.
    testWidgets(
      'back() walks the tabs the user saw',
      (tester) async {
        final router = _router();
        await pumpRouterAppWithConfig(tester, router);
        unawaited(router.push(const NamedRoute('TabsRoute')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
        for (final index in [1, 2]) {
          tabs.setActiveIndex(index);
          await tester.pumpAndSettle();
        }

        await tester.binding.handlePushRoute('/tabs/feed');
        await tester.pumpAndSettle();
        expectTopPage(router, 'FeedTab');
        expect(router.navigationHistory.length, 5);

        final walk = [router.currentUrl];
        for (
          var i = 0;
          i < 8 && router.navigationHistory.canNavigateBack;
          i++
        ) {
          router.back();
          await tester.pumpAndSettle();
          walk.add(router.currentUrl);
        }
        expect(walk, [
          '/tabs/feed',
          '/tabs/settings',
          '/tabs/mail',
          '/tabs/feed',
          '/',
        ]);
      },
      skip: kIsWeb,
    );
  });
}

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
    ),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('FeedTab'),
            NamedRoute<Object?>('MailTab'),
            NamedRoute<Object?>('SettingsTab'),
          ],
        ),
      ),
      children: [
        for (final (name, path) in [
          ('FeedTab', 'feed'),
          ('MailTab', 'mail'),
          ('SettingsTab', 'settings'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => Text(name),
          ),
      ],
    ),
  ],
);
