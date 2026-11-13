import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A nested redirect whose target starts with a path param opens its target
// when the param's value holds a ':'.
// Headless test: auto_route/test/redirect_target_colon_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('redirect target with a colon', () {
    Widget page(String text) => Scaffold(body: SafeArea(child: Text(text)));

    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'SlotsRoute',
          path: '/slots',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'SlotListRoute',
              path: '',
              builder: (_, _) => page('SlotListRoute'),
            ),
            NamedRouteDef(
              name: 'SlotRoute',
              path: ':time',
              builder: (_, data) =>
                  page('Slot ${data.params.getString('time')}'),
            ),
            RedirectRoute(path: 'at/:time', redirectTo: ':time'),
          ],
        ),
      ],
    );

    // Steps: start the app at the link '/slots/at/user:5'.
    // Was: the slot "5" showed.
    // Should: the slot "user:5" shows.
    testWidgets('An app started at /slots/at/user:5 opens that slot', (
      tester,
    ) async {
      final app = router();
      await pumpAppAtDeepLink(
        tester,
        '/slots/at/user:5',
        // Made inside the app, so the config reads the link.
        Builder(builder: (_) => MaterialApp.router(routerConfig: app.config())),
      );

      expect(find.text('Slot user:5'), findsOneWidget);
    });
  });
}
