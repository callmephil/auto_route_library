import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A push called right after popUntilRoot, in a handler that pushed pages
// before it, stays: the pages pushed earlier leave as popUntilRoot is called,
// as Flutter's Navigator changes its history at each call.
// Headless test: auto_route/test/pop_until_then_push_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop until then push in one turn', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home and tap 'Wizard, then result'. Its handler pushes the
    // two steps of a wizard, calls popUntilRoot and pushes the result page,
    // with no await between the calls. Go back.
    // Was: the result page was closed with the wizard's pages, the navigator
    // threw its assertion about an overlay entry removed twice, and the
    // screen stayed empty.
    // Should: the result page is on screen, over Home, and back shows Home.
    testWidgets('A push after popUntilRoot stays on screen', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (context, _) => page('HomeRoute', [
              TextButton(
                onPressed: () {
                  final stack = context.router;
                  unawaited(stack.push(const NamedRoute('StepOneRoute')));
                  unawaited(stack.push(const NamedRoute('StepTwoRoute')));
                  stack.popUntilRoot();
                  unawaited(stack.push(const NamedRoute('ResultRoute')));
                },
                child: const Text('Wizard, then result'),
              ),
            ]),
          ),
          for (final (name, path) in [
            ('StepOneRoute', '/step-one'),
            ('StepTwoRoute', '/step-two'),
            ('ResultRoute', '/result'),
          ])
            NamedRouteDef(
              name: name,
              path: path,
              builder: (_, _) => page(name),
            ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Wizard, then result'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'ResultRoute',
      ]);
      expect(find.text('ResultRoute'), findsOneWidget);
      await expectBrowserUrl('/result');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
    });
  });
}
