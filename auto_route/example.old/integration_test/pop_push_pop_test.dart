import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a pop, a push of the same page again and a pop in one turn
// end on the entry of the page under, as the same calls a frame apart do.
// Headless test: auto_route/test/web/one_turn_history_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop, push, pop', () {
    // Steps: on Home, push A. On A, tap 'Close, reopen, close', which pops
    // A, pushes A again and pops it, in the same turn.
    // Was: the browser held '/', '/a', '/', and back showed A, a page
    // already closed.
    // Should: the browser stands on Home's entry.
    // Native behavior: the HTML History API; back(), pushState and back()
    // one after another end on the entry before.
    // Web only: off the web the router's history records each change as it
    // comes.
    testWidgets(
      'A pop, a push of the same page and a pop in one turn end on Home',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [('HomeRoute', '/'), ('ARoute', '/a')])
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
                            final shown = context.router..pop();
                            unawaited(shown.push(const NamedRoute('ARoute')));
                            shown.pop();
                          },
                          child: const Text('Close, reopen, close'),
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

        await tester.tap(find.text('Close, reopen, close'));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home);
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
