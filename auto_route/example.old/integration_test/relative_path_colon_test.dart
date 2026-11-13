import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A relative path whose first segment holds a ':' opens the page it names.
// Headless test: auto_route/test/relative_path_colon_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('relative path with a colon', () {
    // Steps: in the nested router of '/', pushPath the id.
    // Was: 'user:5' opened the item '5'; '12:30' threw a FormatException.
    // Should: the item with that id shows.
    for (final id in ['user:5', '12:30']) {
      testWidgets('pushPath("$id") in a nested router opens the item "$id"', (
        tester,
      ) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'ItemsRoute',
              path: '/',
              builder: (_, _) => const AutoRouter(),
              children: [
                NamedRouteDef(
                  name: 'ListRoute',
                  path: '',
                  builder: (_, _) =>
                      const Scaffold(body: SafeArea(child: Text('ListRoute'))),
                ),
                NamedRouteDef(
                  name: 'ItemRoute',
                  path: ':id',
                  builder: (_, data) => Scaffold(
                    body: SafeArea(
                      child: Text('Item ${data.params.getString('id')}'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router);
        final nested = router.innerRouterOf<StackRouter>('ItemsRoute')!;
        unawaited(nested.pushPath(id));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Item $id'), findsOneWidget);
        expect(router.currentUrl, '/$id');
      });
    }
  });
}
