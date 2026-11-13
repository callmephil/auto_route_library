import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A replace with a page of the same route keeps the screen and the wait of
// the code that opened it, which gets the result the screen closes with, as
// Flutter's Navigator keeps a route, with its pending future, for a page of
// the same type and key.
// Headless test:
// auto_route/test/simple_router/taken_over_screen_keeps_caller_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('taken over screen keeps caller', () {
    // Steps: open Home, push<int> the picker for item 1. Replace it with the
    // picker for item 2, which keeps the screen. Tap 'Answer 7'.
    // Was: the first push finished with null as the replace went in, so the
    // 7 reached no one.
    // Should: the picker shows item 2, and the code that opened it gets 7.
    testWidgets('replace with a page of the same route keeps the caller of '
        'the screen waiting', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'PickerRoute',
            path: '/picker/:id',
            builder: (context, data) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Text('Picker ${data.params.rawMap['id']}'),
                    TextButton(
                      onPressed: () => unawaited(context.router.maybePop(7)),
                      child: const Text('Answer 7'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      final results = <String>[];
      unawaited(
        router
            .push<int>(const NamedRoute('PickerRoute', params: {'id': 1}))
            .then((value) => results.add('got ${value ?? 'null'}')),
      );
      await tester.pumpAndSettle();

      unawaited(
        router.replace(const NamedRoute('PickerRoute', params: {'id': 2})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Picker 2'), findsOneWidget);
      expect(results, isEmpty);

      await tester.tap(find.text('Answer 7'));
      await tester.pumpAndSettle();

      expect(results, ['got 7']);
      expect(find.text('HomeRoute'), findsOneWidget);
    });
  });
}
