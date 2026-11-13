import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A url whose fragment holds a '?' opens its page, from a link or a push.
// Headless test: auto_route/test/fragment_question_mark_url_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('fragment with a question mark', () {
    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
        ),
        NamedRouteDef(
          name: 'BookRoute',
          path: '/books/:id',
          builder: (_, data) => Scaffold(
            body: SafeArea(
              child: Text(
                'Book ${data.params.getString('id')} #${data.fragment}',
              ),
            ),
          ),
        ),
      ],
    );

    // Steps: start the app at /books/a%20b#what?.
    // Was: RangeError, and no page.
    // Should: the book page shows the fragment 'what?'.
    testWidgets('An app started at a url whose fragment holds a "?" opens it', (
      tester,
    ) async {
      final app = router();
      await pumpAppAtDeepLink(
        tester,
        '/books/a%20b#what?',
        // Made inside the app, so the config reads the link.
        Builder(
          builder: (_) => MaterialApp.router(routerConfig: app.config()),
        ),
      );

      expect(find.text('Book a b #what?'), findsOneWidget);
      expect(app.currentUrl, '/books/a b#what?');
    });

    // Steps: open Home, push the book page with the fragment 'what?'.
    // Was: RangeError, and the page didn't open.
    // Should: the book page shows, and the url ends in '#what?'.
    testWidgets('A page pushed with a "?" in its fragment opens', (
      tester,
    ) async {
      final app = router();
      await pumpRouterApp(tester, app);
      unawaited(
        app.push(
          const NamedRoute(
            'BookRoute',
            params: {'id': 'a b'},
            fragment: 'what?',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Book a b #what?'), findsOneWidget);
      expect(app.currentUrl, '/books/a b#what?');
    });
  });
}
