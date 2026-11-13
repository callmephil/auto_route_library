import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// An empty query value reads as absent, however the page was opened.
// Headless test: auto_route/test/empty_query_value_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Empty query value', () {
    Widget page(String text) => Scaffold(body: SafeArea(child: Text(text)));

    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'BookRoute',
          path: '/books/:id',
          builder: (_, data) => page('Query ${data.queryParams.rawMap}'),
        ),
      ],
    );

    // Steps: open the app at /books/1?a=1&tag=x&b=&c&tag=.
    // Was: the page read b, c and the second tag as empty texts, while the
    // url the router wrote, and so a reload, had no b or c.
    // Should: the page reads a and tag only, as its url does.
    testWidgets('A link with empty query values shows what its url reads', (
      tester,
    ) async {
      final app = router();
      await pumpAppAtDeepLink(
        tester,
        '/books/1?a=1&tag=x&b=&c&tag=',
        // Made inside the app, so the config reads the link.
        Builder(builder: (_) => MaterialApp.router(routerConfig: app.config())),
      );

      expect(
        (find.text('Query {a: 1, tag: x}').evaluate().length, app.currentUrl),
        (1, '/books/1?a=1&tag=x'),
      );
      await expectBrowserUrl('/books/1?a=1&tag=x');
    });

    // Steps: on Home, push BookRoute with the query params a '1' and b ''.
    // Was: the page read b as an empty text, which its url leaves out.
    // Should: the page reads a only.
    testWidgets('A page pushed with an empty query value reads it as absent', (
      tester,
    ) async {
      final app = router();
      await pumpRouterApp(tester, app);
      unawaited(
        app.push(
          const NamedRoute(
            'BookRoute',
            params: {'id': '1'},
            queryParams: {'a': '1', 'b': ''},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (find.text('Query {a: 1}').evaluate().length, app.currentUrl),
        (1, '/books/1?a=1'),
      );
    });
  });
}
