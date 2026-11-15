import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Two calls of router.back() in one handler step back twice, as two calls of
// history.back() in one task take a browser back two entries.
// Headless test: auto_route/test/back_twice_in_one_turn_test.dart
//
// Off the web only: the test is about the app's own history. On the web
// back() is the browser's history.back(), and the browser takes both steps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back twice in one turn', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home, the list and an item. Tap 'Back to start'. Its
    // handler calls back() twice, with no await between the calls.
    // Was: only the item closed, and the list stayed on screen.
    // Should: Home is on screen and the history has no step back left.
    testWidgets(
      'Both steps back are taken',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('ListRoute', '/list'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => page(name),
              ),
            NamedRouteDef(
              name: 'ItemRoute',
              path: '/item',
              builder: (context, _) => page('ItemRoute', [
                TextButton(
                  onPressed: () {
                    final stack = context.router;
                    for (var i = 0; i < 2; i++) {
                      stack.back();
                    }
                  },
                  child: const Text('Back to start'),
                ),
              ]),
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        for (final name in ['ListRoute', 'ItemRoute']) {
          unawaited(router.push(NamedRoute(name)));
          await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Back to start'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(find.text('ListRoute'), findsNothing);
        expect(router.navigationHistory.length, 1);
        expect(router.canNavigateBack, isFalse);
      },
      // On the web back() is the browser's history.back().
      skip: kIsWeb,
    );
  });
}
