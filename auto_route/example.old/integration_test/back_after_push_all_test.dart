import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, pages the app opens together have a browser entry each, so
// the back button closes them one by one.
// Headless test: auto_route/test/web/pages_opened_together_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where each route
// pushed is closed by a system back of its own, whether it was pushed alone
// or with others. Web only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pages opened together', () {
    // Steps: on Home, pushAll A, B and C. Press the browser's back button
    // three times.
    // Should: C shows at '/c', three entries over the entry of Home, and
    // back shows B, A, then Home.
    testWidgets(
      'Back after pushAll closes the pages one by one',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex()!;

        unawaited(
          router.pushAll(const [
            NamedRoute('ARoute'),
            NamedRoute('BRoute'),
            NamedRoute('CRoute'),
          ]),
        );
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 3);
        await expectBrowserUrl('/c');

        await expectBrowserBackWalk(tester, router, [
          ('BRoute', '/b'),
          ('ARoute', '/a'),
          ('HomeRoute', '/'),
        ]);
      },
      skip: !kIsWeb,
    );
  });
}
