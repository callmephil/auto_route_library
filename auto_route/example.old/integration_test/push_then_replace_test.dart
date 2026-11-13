import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a push and a replace of the pushed page in one frame write one
// new browser entry, and the page under keeps its own.
// Headless test: auto_route/test/web/push_then_replace_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('push then replace', () {
    // Steps: on Home, tap 'Open B', which pushes A and, after an await that
    // completes at once, replaces A with B and a note the url can't carry,
    // all before the next frame. Then press the browser's back button, then
    // its forward button.
    // Was: B's url went over Home's entry, so back had no entry of the app
    // to go to; forward then reopened B without its note.
    // Should: B gets a new entry, back goes to Home, and forward reopens B
    // with its note.
    // Native behavior: the HTML History API; pushState then replaceState
    // leaves the entry before as it was, and one new entry with the last url.
    // Web only: off the web the router's history records each change as it
    // comes.
    testWidgets(
      'A push and a replace in one frame keep the entry of the page under',
      (tester) async {
        // Pushes A, and replaces it with B a moment later, before the frame.
        void openB(StackRouter router) {
          unawaited(router.push(const NamedRoute('ARoute')));
          unawaited(
            Future.delayed(
              .zero,
              () => router.replace(
                const NamedRoute('BRoute', args: 'draft 7'),
              ),
            ),
          );
        }

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
                          onPressed: () => openB(context.router),
                          child: const Text('Open B'),
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

        await tester.tap(find.text('Open B'));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/b');

        pressBrowserBack();
        await expectBrowserEntry(home);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/');
        final onHome = find.text('HomeRoute').evaluate().length;

        pressBrowserForward();
        await expectBrowserEntry(home + 1);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/b');
        expect((onHome, find.text('draft 7').evaluate().length), (1, 1));
      },
      skip: !kIsWeb,
    );
  });
}
