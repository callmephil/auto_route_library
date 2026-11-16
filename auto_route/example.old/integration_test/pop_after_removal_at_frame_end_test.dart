import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A pop right after a callback at the frame's end took a page off closes
// the page under that one, as Flutter's Navigator no longer counts a route
// as present from the call that removed it.
// Headless test: auto_route/test/pop_after_removal_at_frame_end_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop after removal at frame end', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home and the three steps of a wizard. Tap 'Close the
    // wizard' on the third. Its handler takes the third step off with
    // removeLast, and registers a callback for the end of the frame that
    // takes the second step off the same way and then, in a microtask, pops.
    // Was: the first step stayed on screen. The pop had closed the route of
    // the second step, a page already gone.
    // Should: the first step closes too, and Home is on screen.
    testWidgets('The page under one taken off as the frame ends closes', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          for (final (name, path) in [
            ('HomeRoute', '/'),
            ('StepOneRoute', '/step-one'),
            ('StepTwoRoute', '/step-two'),
          ])
            NamedRouteDef(
              name: name,
              path: path,
              builder: (_, _) => page(name),
            ),
          NamedRouteDef(
            name: 'StepThreeRoute',
            path: '/step-three',
            builder: (context, _) => page('StepThreeRoute', [
              TextButton(
                onPressed: () {
                  final stack = context.router;
                  // Registered first, so it runs before any callback of the
                  // router at the end of the same frame.
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    stack.removeLast();
                    scheduleMicrotask(stack.pop);
                  });
                  stack.removeLast();
                },
                child: const Text('Close the wizard'),
              ),
            ]),
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      for (final name in ['StepOneRoute', 'StepTwoRoute', 'StepThreeRoute']) {
        unawaited(router.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Close the wizard'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(find.text('StepOneRoute'), findsNothing);
      await expectBrowserUrl('/');
    });
  });
}
