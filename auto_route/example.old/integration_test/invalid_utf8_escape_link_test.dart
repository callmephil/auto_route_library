import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// An app started at a link with an escape that is not valid UTF-8 shows a
// page.
// Headless test: auto_route/test/invalid_utf8_escape_link_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('invalid UTF-8 escape in a link', () {
    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
        ),
        NamedRouteDef(
          name: 'SearchRoute',
          path: '/search',
          builder: (_, data) => Scaffold(
            body: SafeArea(
              child: Text(
                'Search ${data.queryParams.optString('q') ?? 'none'}',
              ),
            ),
          ),
        ),
        NamedRouteDef(
          name: 'BookRoute',
          path: '/books/:id',
          builder: (_, data) => Scaffold(
            body: SafeArea(child: Text('Book ${data.params.getString('id')}')),
          ),
        ),
      ],
    );

    // Steps: start the app at the link.
    // Was: no page at all.
    // Should: the link's page shows, with U+FFFD for the bad bytes.
    for (final (link, page) in [
      ('/books/%FF', 'Book �'),
      ('/search?q=%FF', 'Search �'),
    ]) {
      testWidgets(
        'An app started at $link shows its page',
        (tester) async {
          final app = router();
          await pumpAppAtDeepLink(
            tester,
            link,
            // Made inside the app, so the config reads the link.
            Builder(
              builder: (_) => MaterialApp.router(routerConfig: app.config()),
            ),
          );

          expect(find.text(page), findsOneWidget);
        },
      );
    }
  });
}
