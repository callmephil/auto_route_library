import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// Off the web, router.back() closes one page per call after pushAll, as the
// browser's back button does on the web.
// Headless test: auto_route/test/back_after_opening_pages_together_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where each route
// pushed is closed by a pop of its own, whether it was pushed alone or with
// others. Off the web only: on the web, back() is the browser's own back
// step (see back_after_push_all_test.dart).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pages opened together, off the web', () {
    // Steps: on Home, pushAll A, B and C. Call back() three times.
    // Was: the first back() closed A, B and C at once and showed Home.
    // Should: back() shows B, A, then Home.
    testWidgets(
      'back() after pushAll closes the pages one by one',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterAppWithConfig(tester, router);

        unawaited(
          router.pushAll(const [
            NamedRoute('ARoute'),
            NamedRoute('BRoute'),
            NamedRoute('CRoute'),
          ]),
        );
        await tester.pumpAndSettle();

        final shown = <String>[];
        for (var i = 0; i < 3; i++) {
          router.back();
          await tester.pumpAndSettle();
          shown.add(router.current.name);
        }
        expect(shown, ['BRoute', 'ARoute', 'HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
      },
      skip: kIsWeb,
    );
  });
}
