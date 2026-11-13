import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a replace and a pop in one turn end on the browser entry of the
// page under, as the same calls a frame apart do.
// Headless test: auto_route/test/web/one_turn_history_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace then pop', () {
    // Steps: on Home, push A. On A, tap 'Swap and close', which replaces A
    // with B and pops B in the same turn.
    // Was: the browser stood on a third entry holding '/', with A's entry
    // under it, so its back button reopened A, a page already closed.
    // Should: the browser stands on Home's entry.
    // Native behavior: the HTML History API; history.replaceState followed
    // by history.back() ends on the entry before.
    // Web only: off the web the router's history records each change as it
    // comes.
    testWidgets(
      'A replace and a pop in one turn end on the entry of the page under',
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
                          onPressed: () {
                            unawaited(
                              context.router.replace(
                                const NamedRoute('BRoute'),
                              ),
                            );
                            context.router.pop();
                          },
                          child: const Text('Swap and close'),
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

        await tester.tap(find.text('Swap and close'));
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
