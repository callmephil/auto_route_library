import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A replace and two pops in one handler close the new page and the page
// under the replaced one, as Flutter's Navigator does after pushReplacement,
// pop and pop: the page the app closed does not come back.
// Headless test: auto_route/test/pop_after_replace_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop after replace in one turn', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home, the cart and the payment page. Tap 'Cancel the
    // order'. Its handler replaces the payment page with a receipt and pops
    // twice, with no await between the calls. Go back.
    // Was: the cart stayed open and showed again, though the app had closed
    // it.
    // Should: Home is on screen, at its url, and back has no page to close.
    testWidgets('The page under the replaced one closes with the second pop', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          for (final (name, path) in [
            ('HomeRoute', '/'),
            ('CartRoute', '/cart'),
            ('ReceiptRoute', '/receipt'),
          ])
            NamedRouteDef(
              name: name,
              path: path,
              builder: (_, _) => page(name),
            ),
          NamedRouteDef(
            name: 'PaymentRoute',
            path: '/payment',
            builder: (context, _) => page('PaymentRoute', [
              TextButton(
                onPressed: () {
                  final stack = context.router;
                  unawaited(stack.replace(const NamedRoute('ReceiptRoute')));
                  for (var i = 0; i < 2; i++) {
                    stack.pop();
                  }
                },
                child: const Text('Cancel the order'),
              ),
            ]),
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      for (final name in ['CartRoute', 'PaymentRoute']) {
        unawaited(router.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Cancel the order'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      for (final closed in ['CartRoute', 'PaymentRoute', 'ReceiptRoute']) {
        expect(find.text(closed), findsNothing);
      }
      await expectBrowserUrl('/');
    });
  });
}
