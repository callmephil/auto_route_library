import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// pushAndPopUntil with Flutter's ModalRoute.withName keeps the named page
// when that page was pushed in the same handler, as Flutter's Navigator
// hands the predicate the route of a push made just before.
// Headless test:
// auto_route/test/push_and_pop_until_with_name_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('push and pop until with name in one turn', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home and tap 'Open the order'. Its handler pushes the
    // orders list and calls pushAndPopUntil with the order's page and
    // ModalRoute.withName('OrdersRoute'), with no await between the calls.
    // Go back.
    // Was: the order's page was the only page left, so back had no page to
    // show.
    // Should: the order's page is on screen and back shows the orders list.
    testWidgets('Back from the new page shows the page named to keep', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (context, _) => page('HomeRoute', [
              TextButton(
                onPressed: () {
                  final stack = context.router;
                  unawaited(stack.push(const NamedRoute('OrdersRoute')));
                  unawaited(
                    stack.pushAndPopUntil(
                      const NamedRoute('OrderRoute'),
                      predicate: ModalRoute.withName('OrdersRoute'),
                    ),
                  );
                },
                child: const Text('Open the order'),
              ),
            ]),
          ),
          for (final (name, path) in [
            ('OrdersRoute', '/orders'),
            ('OrderRoute', '/order'),
          ])
            NamedRouteDef(
              name: name,
              path: path,
              builder: (_, _) => page(name),
            ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Open the order'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'OrdersRoute',
        'OrderRoute',
      ]);
      expect(find.text('OrderRoute'), findsOneWidget);
      await expectBrowserUrl('/order');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'OrdersRoute',
      ]);
      expect(find.text('OrdersRoute'), findsOneWidget);
    });
  });
}
