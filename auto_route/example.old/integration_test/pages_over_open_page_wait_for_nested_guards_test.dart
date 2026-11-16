import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigation into the nested router of an open page, with pages pushed
// over that page, keeps those pages, and the dialog over them, when a guard
// in that router says no. They close only once the guard lets it in.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document on screen; on iOS a segue whose shouldPerformSegue answers
// false leaves the view controllers as they are.
// Headless test:
// auto_route/test/guards/pages_over_open_page_wait_for_nested_guards_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pages over open page wait for nested guards', () {
    Widget page(String name) => Scaffold(
      body: SafeArea(child: Center(child: Text(name))),
    );

    // Steps: Home holds a nested router on Feed. Settings is pushed over
    // Home, and a dialog over Settings. The app calls navigatePath to
    // message 13 in Home's router, whose guard says no.
    // Was: Settings and the dialog closed and stayed closed.
    // Should: Settings and the dialog stay, at the url of Settings.
    testWidgets('A rejected path into the router under Settings keeps it', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef.shell(
            name: 'HomeRoute',
            path: '/',
            children: [
              NamedRouteDef(
                name: 'FeedRoute',
                path: '',
                builder: (_, _) => page('FeedRoute'),
              ),
              NamedRouteDef(
                name: 'MessageRoute',
                path: 'message/:id',
                guards: [
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
                ],
                builder: (_, _) => page('MessageRoute'),
              ),
            ],
          ),
          NamedRouteDef(
            name: 'SettingsRoute',
            path: '/settings',
            builder: (_, _) => page('SettingsRoute'),
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Draft')),
      );
      await tester.pumpAndSettle();

      unawaited(router.navigatePath('/message/13'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'SettingsRoute',
      ]);
      expect(find.text('Draft'), findsOneWidget);
      expect(router.currentUrl, '/settings');
      await expectBrowserUrl('/settings');
    });
  });
}
