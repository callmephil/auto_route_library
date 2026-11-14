import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// With usesPathAsKey, a page a link opened is not pushed a second time when
// the app navigates to it.
// Headless test: auto_route/test/path_key_link_then_navigate_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('path key from a link and from a route', () {
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
              usesPathAsKey: true,
              builder: (_, data) =>
                  page('Slot ${data.params.getString('time')}'),
            ),
          ],
        ),
      ],
    );

    // Steps: start the app at '/slots/user:5', then navigate the nested router
    // to the slot 'user:5'.
    // Was: the slot page was on the nested stack twice.
    // Should: one slot page. Off the web it sits over the slot list, which
    // the link opens below it as a prefix match. On the web a url opens the
    // one page it names, as a browser loads the one document at an address,
    // so the slot is the nested stack's only page.
    testWidgets('A slot opened by its link and then by its route is one page', (
      tester,
    ) async {
      final app = router();
      await pumpAppAtDeepLink(
        tester,
        '/slots/user:5',
        // Made inside the app, so the config reads the link.
        Builder(builder: (_) => MaterialApp.router(routerConfig: app.config())),
      );
      final nested = app.innerRouterOf<StackRouter>('SlotsRoute');
      unawaited(
        nested?.navigate(
          const NamedRoute('SlotRoute', params: {'time': 'user:5'}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (
          nested?.stackData.map((data) => data.name).join(' '),
          find.text('Slot user:5').evaluate().length,
        ),
        (kIsWeb ? 'SlotRoute' : 'SlotListRoute SlotRoute', 1),
      );
    });
  });
}
