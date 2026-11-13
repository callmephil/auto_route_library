import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A fragment given to a child route reaches the url and the page when the
// child is opened with its parent.
// Headless test: auto_route/test/child_route_fragment_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('child route fragment', () {
    Widget page(String text) => Scaffold(body: SafeArea(child: Text(text)));

    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'HelpRoute',
          path: '/help',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'HelpHomeRoute',
              path: '',
              builder: (_, _) => page('HelpHomeRoute'),
            ),
            NamedRouteDef(
              name: 'DocsRoute',
              path: 'docs',
              builder: (_, data) => page('Docs at [${data.fragment}]'),
            ),
          ],
        ),
      ],
    );

    // Steps: on Home, push HelpRoute with the child DocsRoute(fragment: 'faq').
    // Was: the page read '' and the url was /help/docs.
    // Should: the page reads 'faq' and the url is /help/docs#faq.
    testWidgets('A child pushed with its parent keeps its fragment', (
      tester,
    ) async {
      final app = router();
      await pumpRouterApp(tester, app);
      unawaited(
        app.push(
          const NamedRoute(
            'HelpRoute',
            children: [NamedRoute('DocsRoute', fragment: 'faq')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (find.text('Docs at [faq]').evaluate().length, app.currentUrl),
        (1, '/help/docs#faq'),
      );
    });
  });
}
