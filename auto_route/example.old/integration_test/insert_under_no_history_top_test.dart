import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// insert() of a page below the top keeps a top page that keeps no history,
// as Flutter's Navigator keeps the route on top when a page is added below
// it.
// Headless test: auto_route/test/insert_under_no_history_top_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('insert under no history top', () {
    // Steps: open Home and push the promo page, which keeps no history. Tap
    // 'Add settings below' on it, which inserts the settings page at the
    // bottom of the stack. Go back twice.
    // Was: the promo page closed as the settings page went in under it.
    // Should: the promo page stays on screen; back shows Home, then the
    // settings page.
    testWidgets('Inserting below keeps the page on screen', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'PromoRoute',
            path: '/promo',
            keepHistory: false,
            builder: (context, _) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    const Text('PromoRoute'),
                    TextButton(
                      onPressed: () => unawaited(
                        context.router.insert(
                          const NamedRoute('SettingsRoute'),
                        ),
                      ),
                      child: const Text('Add settings below'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          NamedRouteDef(
            name: 'SettingsRoute',
            path: '/settings',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('SettingsRoute'))),
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('PromoRoute')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add settings below'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'SettingsRoute',
        'HomeRoute',
        'PromoRoute',
      ]);
      expect(find.text('PromoRoute'), findsOneWidget);
      await expectBrowserUrl('/promo');

      await systemBack(tester);
      final shownAfterFirstBack = find.text('HomeRoute').evaluate().length;
      await systemBack(tester);

      expect(shownAfterFirstBack, 1);
      expect(find.text('SettingsRoute'), findsOneWidget);
    });
  });
}
