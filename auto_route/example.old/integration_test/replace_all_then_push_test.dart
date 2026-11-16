import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, replaceAll and a push in one turn give each page a browser
// entry, so the browser's back button returns to the page replaceAll left.
// Headless test: auto_route/test/web/one_turn_history_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaceAll then push', () {
    // Steps: on Home, push A. On A, tap 'Open C and B', which calls
    // replaceAll with C and pushes B in the same turn. Then press the
    // browser's back button.
    // Was: C got no entry; back from B went to Home's entry and put Home on
    // top of C and B.
    // Should: C has Home's entry, the app's first, since replaceAll closed
    // Home and A, and B the one over it; back from B goes to C's entry and
    // shows C.
    // Native behavior: Flutter's Navigator, where back from the one route
    // left by pushAndRemoveUntil leaves the app, and each route pushed after
    // it is closed by a back of its own.
    // Web only: off the web the router's history records each change as it
    // comes.
    testWidgets(
      'replaceAll and a push in one turn get a browser entry each',
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
                          onPressed: () {
                            unawaited(
                              context.router.replaceAll(const [
                                NamedRoute('CRoute'),
                              ]),
                            );
                            unawaited(
                              context.router.push(const NamedRoute('BRoute')),
                            );
                          },
                          child: const Text('Open C and B'),
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

        await tester.tap(find.text('Open C and B'));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/b');

        pressBrowserBack();
        await expectBrowserEntry(home);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/c');
        expect(find.text('CRoute'), findsOneWidget);
      },
      skip: !kIsWeb,
    );
  });
}
