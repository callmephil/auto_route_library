import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A push called right after popUntilRouteWithPath, in a handler that pushed
// pages before it, stays: the pages pushed earlier leave as the pop is
// called, as Flutter's Navigator changes its history at each call.
// Headless test:
// auto_route/test/pop_until_path_or_unscoped_then_push_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop until path then push in one turn', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home and tap 'Order, then receipt'. Its handler pushes the
    // cart and the payment page, calls popUntilRouteWithPath with the cart's
    // path and pushes the receipt, with no await between the calls. Go back.
    // Was: the receipt was closed with the payment page, and the cart
    // showed.
    // Should: the receipt is on screen, over the cart, and back shows the
    // cart.
    testWidgets('A push after popUntilRouteWithPath stays on screen', (
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
                  unawaited(stack.push(const NamedRoute('CartRoute')));
                  unawaited(stack.push(const NamedRoute('PaymentRoute')));
                  stack.popUntilRouteWithPath('/cart');
                  unawaited(stack.push(const NamedRoute('ReceiptRoute')));
                },
                child: const Text('Order, then receipt'),
              ),
            ]),
          ),
          for (final (name, path) in [
            ('CartRoute', '/cart'),
            ('PaymentRoute', '/payment'),
            ('ReceiptRoute', '/receipt'),
          ])
            NamedRouteDef(
              name: name,
              path: path,
              builder: (_, _) => page(name),
            ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Order, then receipt'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'CartRoute',
        'ReceiptRoute',
      ]);
      expect(find.text('ReceiptRoute'), findsOneWidget);
      await expectBrowserUrl('/receipt');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'CartRoute',
      ]);
      expect(find.text('CartRoute'), findsOneWidget);
    });
  });
}
