import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A Set given as a query param reads back as its values, as a List does.
// Headless test: auto_route/test/set_query_param_read_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Set query param', () {
    Widget page(String text) => Scaffold(body: SafeArea(child: Text(text)));

    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'TagsRoute',
          path: '/tags',
          builder: (_, data) => page(
            'Tags ${data.queryParams.optList('tags')?.join(' + ') ?? ''}',
          ),
        ),
      ],
    );

    // Steps: on Home, push TagsRoute with the query param tags {red, blue}.
    // Was: the page showed the one tag '{red, blue}'.
    // Should: the page shows red and blue, and the url names both.
    testWidgets('A page pushed with a Set shows each of its values', (
      tester,
    ) async {
      final app = router();
      await pumpRouterApp(tester, app);
      unawaited(
        app.push(
          const NamedRoute(
            'TagsRoute',
            queryParams: {
              'tags': {'red', 'blue'},
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (find.text('Tags red + blue').evaluate().length, app.currentUrl),
        (1, '/tags?tags=red&tags=blue'),
      );
    });
  });
}
