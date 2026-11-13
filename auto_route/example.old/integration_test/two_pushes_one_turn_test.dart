import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, two pushes in one turn get a browser entry each.
// Headless test: auto_route/test/web/two_pushes_one_turn_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('two pushes in one turn', () {
    // Steps: on Home, tap 'Open A and B', which pushes A and B, with a note
    // the url can't carry, in one turn. Then press the browser's back button,
    // then its forward button.
    // Was: only B got an entry; back skipped A and went to Home, and forward
    // reopened B without its note.
    // Should: back goes to A, and forward reopens B with its note.
    // Native behavior: the HTML History API; two history.pushState calls add
    // two entries, as Flutter's own Navigator writes each push to the engine.
    // Web only: off the web the router's history records each push as it
    // comes.
    testWidgets(
      'Two pushes in one turn get a browser entry each',
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
                builder: (context, data) => Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        Text(name),
                        if (data.args case final String note) Text(note),
                        TextButton(
                          onPressed: () {
                            unawaited(
                              context.router.push(const NamedRoute('ARoute')),
                            );
                            unawaited(
                              context.router.push(
                                const NamedRoute('BRoute', args: 'draft 7'),
                              ),
                            );
                          },
                          child: const Text('Open A and B'),
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

        await tester.tap(find.text('Open A and B'));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 2);
        await expectBrowserUrl('/b');

        pressBrowserBack();
        await expectBrowserEntry(home + 1);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/a');
        final onA = find.text('ARoute').evaluate().length;

        pressBrowserForward();
        await expectBrowserEntry(home + 2);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/b');
        expect((onA, find.text('draft 7').evaluate().length), (1, 1));
      },
      skip: !kIsWeb,
    );
  });
}
