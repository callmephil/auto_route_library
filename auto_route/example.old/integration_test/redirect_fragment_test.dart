import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A RedirectRoute whose redirectTo ends in a fragment keeps it in the url.
// Headless test: auto_route/test/redirect_fragment_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('redirect fragment', () {
    // Steps: start the app at /help, which redirects to /docs#faq.
    // Was: the url was /docs, and the page read no fragment.
    // Should: the url is /docs#faq, and the page reads 'faq'.
    testWidgets('A redirect to /docs#faq keeps its fragment', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'DocsRoute',
            path: '/docs',
            builder: (_, data) => Scaffold(
              body: SafeArea(child: Text('Docs at [${data.fragment}]')),
            ),
          ),
          RedirectRoute(path: '/help', redirectTo: '/docs#faq'),
        ],
      );
      await pumpAppAtDeepLink(
        tester,
        '/help',
        // Made inside the app, so the config reads the link.
        Builder(
          builder: (_) => MaterialApp.router(routerConfig: router.config()),
        ),
      );

      expect(find.text('Docs at [faq]'), findsOneWidget);
      expect(router.currentUrl, '/docs#faq');
    });
  });
}
