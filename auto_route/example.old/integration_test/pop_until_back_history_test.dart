import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, router.back() after popUntilRoot or popUntil reopens none of
// the pages they closed.
// Headless test: auto_route/test/pop_until_history_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  RootStackRouter buildRouter() => .build(
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
                    onPressed: context.router.back,
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Future<RootStackRouter> pumpFourPages(WidgetTester tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());
    for (final name in ['ARoute', 'BRoute', 'CRoute']) {
      unawaited(router.push(NamedRoute(name)));
      await tester.pumpAndSettle();
    }
    expect(find.text('CRoute'), findsOneWidget);
    return router;
  }

  group('pop until back history', () {
    // Steps: push A, B and C over Home and call popUntilRoot. Then tap the
    // 'Back' button, whose handler is the router's back method.
    // Was: B opened again, a page popUntilRoot had just closed.
    // Should: Home stays, alone on the stack.
    // Native behavior: popping to the first route with Navigator.popUntil,
    // with popToRootViewController on iOS or with NavController.popBackStack
    // on Android leaves no closed page for back to reopen.
    testWidgets(
      'router.back() after popUntilRoot reopens no closed page',
      (tester) async {
        final router = await pumpFourPages(tester);
        router.popUntilRoot();
        await tester.pumpAndSettle();
        final homesAfterPop = find.text('HomeRoute').evaluate().length;
        expect(router.canNavigateBack, isFalse);

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(
          (homesAfterPop, find.text('HomeRoute').evaluate().length),
          (1, 1),
        );
        expect(find.text('BRoute'), findsNothing);
        expect(router.stack.map((page) => page.name), ['HomeRoute']);
      },
      // On the web the browser keeps the history, and can't delete entries.
      skip: kIsWeb,
    );

    // Steps: push A, B and C over Home, popUntil A, then tap 'Back'.
    // Was: B opened over A.
    // Should: Home shows, alone on the stack.
    testWidgets(
      'router.back() after popUntil returns to the page before',
      (tester) async {
        final router = await pumpFourPages(tester);
        router.popUntil((route) => route.settings.name == 'ARoute');
        await tester.pumpAndSettle();
        expect(find.text('ARoute'), findsOneWidget);

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(find.text('HomeRoute'), findsOneWidget);
        expect(router.stack.map((page) => page.name), ['HomeRoute']);
      },
      skip: kIsWeb,
    );
  });
}
