import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, the browser's back button after popUntilRoot or popUntil
// reopens none of the pages they closed.
// Headless test: auto_route/test/web/pop_until_browser_back_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop until browser back', () {
    // Steps: push A, B and C over Home, tap 'To A' on C, which calls
    // popUntilRouteWithName('ARoute'), then press the browser's back button.
    // Was: the browser stayed on C's entry, now showing '/a', and its back
    // button reopened B, a page popUntil had just closed.
    // Should: popUntil steps the browser back to A's entry, and back then
    // goes to Home's.
    // Native behavior: Android's popBackStack to a destination and iOS's
    // popToViewController drop every screen they close; a web page drops
    // browser entries by going back over them, history.go(-n).
    // Web only: off the web, pop_until_back_history_test.dart covers it.
    testWidgets(
      'The browser back button after popUntil reopens no closed page',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('ARoute', '/a'),
              ('BRoute', '/b'),
              ('CRoute', '/c'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (context, _) => Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        Text(name),
                        TextButton(
                          onPressed: () =>
                              context.router.popUntilRouteWithName('ARoute'),
                          child: const Text('To A'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex()!;
        for (final name in ['ARoute', 'BRoute', 'CRoute']) {
          unawaited(router.push(NamedRoute(name)));
          await tester.pumpAndSettle();
        }
        await expectBrowserUrl('/c');

        await tester.tap(find.text('To A'));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/a');

        pressBrowserBack();
        await expectBrowserEntry(home);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/');
        expect(find.text('HomeRoute'), findsOneWidget);
      },
      skip: !kIsWeb,
    );
  });
}
