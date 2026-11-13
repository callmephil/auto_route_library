import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, popAndPush takes the browser entry of the page it pops, so the
// browser's back button returns to the page under both.
// Headless test: auto_route/test/web/one_turn_history_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('popAndPush browser back', () {
    // Steps: on Home, push A. On A, tap 'Swap for B', which calls
    // popAndPush with B. Then press the browser's back button.
    // Was: the browser held Home's, A's and B's entries, and back from B put
    // A on top of B.
    // Should: B takes A's entry, and back goes to Home.
    // Native behavior: Flutter's Navigator.popAndPushNamed pops the route and
    // pushes the new one in one call; for the browser a pop and a push in one
    // turn are one replace of the entry, as history.replaceState makes it.
    // Web only: off the web the router's history drops the popped page's
    // entry as the pop comes.
    testWidgets(
      'popAndPush takes the entry of the page it pops',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('ARoute', '/a'),
              ('BRoute', '/b'),
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
                          onPressed: () => unawaited(
                            context.router.popAndPush(
                              const NamedRoute('BRoute'),
                            ),
                          ),
                          child: const Text('Swap for B'),
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
        unawaited(router.push(const NamedRoute('ARoute')));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);

        await tester.tap(find.text('Swap for B'));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/b');

        pressBrowserBack();
        await expectBrowserEntry(home);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/');
        expect(
          (find.text('HomeRoute').evaluate().length, router.stack.length),
          (1, 1),
        );
      },
      skip: !kIsWeb,
    );
  });
}
