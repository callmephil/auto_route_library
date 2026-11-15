import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a replace, a push and a pop in one turn end where the same
// calls a frame apart end: on the replacing page's entry.
// Headless test: auto_route/test/web/one_turn_history_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace, push, pop', () {
    // Steps: on Home, push A. On A, tap 'Swap and peek', which replaces A
    // with B, pushes C and pops C in the same turn. Then press the browser's
    // back button.
    // Was: the browser held '/', '/b', '/c', '/b', and back showed C again.
    // Should: the browser stands on B's entry over Home's, and back goes to
    // Home.
    // Native behavior: the HTML History API; replaceState, pushState and
    // back() one after another end on the replaced entry.
    // Web only: off the web the router's history records each change as it
    // comes.
    testWidgets(
      'A replace, a push and a pop in one turn end on the replacing page',
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
                            final shown = context.router;
                            unawaited(
                              shown.replace(const NamedRoute('BRoute')),
                            );
                            unawaited(shown.push(const NamedRoute('CRoute')));
                            shown.pop();
                          },
                          child: const Text('Swap and peek'),
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

        await tester.tap(find.text('Swap and peek'));
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
