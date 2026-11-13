import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The app's '*' not-found page, opened in code, reports the url '/*'.
// Headless test: auto_route/test/wildcard_route_pushed_url_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('not-found page opened in code', () {
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
          builder: (_, data) => page('Book ${data.params.getString('id')}'),
        ),
        NamedRouteDef(
          name: 'UnknownRoute',
          path: '*',
          builder: (_, _) => page('UnknownRoute'),
        ),
      ],
    );

    // Steps: push the book 1, then replace it with the not-found page.
    // Was: the url was '*', which the browser read as /books/*.
    // Should: the not-found page shows at '/*'.
    testWidgets("The not-found page opened in code is at '/*'", (
      tester,
    ) async {
      final app = router();
      await pumpRouterApp(tester, app);
      unawaited(app.push(const NamedRoute('BookRoute', params: {'id': '1'})));
      await tester.pumpAndSettle();
      unawaited(app.replace(const NamedRoute('UnknownRoute')));
      await tester.pumpAndSettle();

      expect(
        (find.text('UnknownRoute').evaluate().length, app.currentUrl),
        (1, '/*'),
      );
      await expectBrowserUrl('/*');
    });
  });
}
