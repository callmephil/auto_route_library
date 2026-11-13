import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link to a guarded tab whose guard answers after the tabs are gone
// leaves the next page's history entry alone.
// Headless test:
// auto_route/test/nested_tabs_router/guarded_tab_link_after_tabs_left_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('guarded tab link after tabs left', () {
    // Steps: tap 'Open profile link', which opens '/home/profile'; ProfileTab's
    // guard takes its time, so FeedTab shows. Tap 'Open settings', which
    // replaces HomeRoute. The guard then lets ProfileTab in. Tap 'Open
    // detail', then go back.
    // Was: StartRoute showed; back skipped SettingsRoute.
    // Should: SettingsRoute shows, as back goes through every screen left
    // with a push on Android, iOS and the web.
    testWidgets('back after a late tab guard shows the page pushed over', (
      tester,
    ) async {
      final decision = Completer<bool>();
      late final RootStackRouter router;
      Widget button(String label, VoidCallback onPressed) => Scaffold(
        body: SafeArea(
          child: TextButton(onPressed: onPressed, child: Text(label)),
        ),
      );
      router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'StartRoute',
            path: '/',
            builder: (_, _) => button(
              'Open profile link',
              () => unawaited(router.navigatePath('/home/profile')),
            ),
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
                builder: (_, _) => button(
                  'Open settings',
                  () => unawaited(
                    router.replace(const NamedRoute('SettingsRoute')),
                  ),
                ),
              ),
              NamedRouteDef(
                name: 'ProfileTab',
                path: 'profile',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    if (await decision.future) resolver.next();
                  }),
                ],
                builder: (_, _) =>
                    const Scaffold(body: SafeArea(child: Text('ProfileTab'))),
              ),
            ],
          ),
          NamedRouteDef(
            name: 'SettingsRoute',
            path: '/settings',
            builder: (_, _) => button(
              'Open detail',
              () => unawaited(router.push(const NamedRoute('DetailRoute'))),
            ),
          ),
          NamedRouteDef(
            name: 'DetailRoute',
            path: '/detail',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('DetailRoute'))),
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      await tester.tap(find.text('Open profile link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      decision.complete(true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(find.text('DetailRoute'), findsOneWidget);
      router.back();
      await tester.pumpAndSettle();

      expect(find.text('Open detail'), findsOneWidget);
      expect(router.urlState.url, '/settings');
    });
  });
}
