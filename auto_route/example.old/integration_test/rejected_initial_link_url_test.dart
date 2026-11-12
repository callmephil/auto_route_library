import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A browser opens the app at its address; when a guard rejects that link, the
// address bar and a reload must not stay on a page the app does not show.
// Native behavior: a browser (and Android's or iOS's launch intent) cannot
// cancel a load the app has already received, so the app owns the url from the
// first frame; Flutter's Router writes whatever the delegate's
// currentConfiguration reports, and reports nothing while it is null.
// Headless test: auto_route/test/guards/initial_reject_url_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('rejected initial link', () {
    // Steps: open the app, built from routerDelegate and
    // routeInformationParser, at '/protected', whose guard rejects it.
    // Should: 'Protected' is never shown and the address bar no longer holds
    // '/protected'. On web the link opens alone, so the stack is empty; off
    // the web the parser includes prefix matches, as Android's deep links put
    // the start destination under the linked screen, so the batch
    // [HomeRoute, ProtectedRoute] keeps the HomeRoute its guards let through.
    testWidgets('The url drops a link a guard rejected', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Text('Home'),
          ),
          NamedRouteDef(
            name: 'ProtectedRoute',
            path: '/protected',
            guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
            builder: (_, _) => const Text('Protected'),
          ),
        ],
      );
      await pumpAppAtDeepLink(
        tester,
        '/protected',
        MaterialApp.router(
          routeInformationParser: router.defaultRouteParser(),
          routerDelegate: router.delegate(),
        ),
      );
      expect(
        router.stack.map((p) => p.name),
        kIsWeb ? isEmpty : ['HomeRoute'],
      );
      expect(find.text('Protected'), findsNothing);
      await expectBrowserUrl('/');
    });
  });
}
