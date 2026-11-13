import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page reading int and bool query params opens from a link that repeats
// their keys, with the last values.
// Headless test: auto_route/test/repeated_query_key_number_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('repeated query key for numbers', () {
    // Steps: ProductsRoute shows `queryParams.getInt('page')` and
    // `queryParams.getBool('sale')`. Start the app at
    // /products?page=1&page=2&sale=false&sale=true.
    // Was: getInt threw MissingRequiredParameterError and the page failed.
    // Should: the page shows page 2, sale true.
    testWidgets(
      'A page reading getInt opens from a link that repeats the key',
      (
        tester,
      ) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
            ),
            NamedRouteDef(
              name: 'ProductsRoute',
              path: '/products',
              builder: (_, data) => Scaffold(
                body: SafeArea(
                  child: Text(
                    'Page ${data.queryParams.getInt('page')}, '
                    'sale ${data.queryParams.getBool('sale')}',
                  ),
                ),
              ),
            ),
          ],
        );
        await pumpAppAtDeepLink(
          tester,
          '/products?page=1&page=2&sale=false&sale=true',
          // Made inside the app, so the config reads the link.
          Builder(
            builder: (_) => MaterialApp.router(routerConfig: router.config()),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Page 2, sale true'), findsOneWidget);
      },
    );
  });
}
