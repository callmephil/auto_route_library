import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, a page the app takes off the stack without a pop, with
// removeLast or navigate to a page underneath, leaves no entry on the way
// back: the browser's back button never shows it again.
// Headless test: auto_route/test/web/native_walk_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where a route removed
// with Navigator.removeRoute or popUntil never comes back on the system
// back. Web only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('removed page', () {
    final calls = <String, void Function(RootStackRouter router)>{
      'removeLast': (router) => router.removeLast(),
      'navigate to a page underneath': (router) =>
          unawaited(router.navigate(const NamedRoute('BRoute'))),
    };
    // Steps: on Home, push A, B and C, then make the call, which leaves B
    // on top. Press the browser's back button twice.
    // Should: B shows at '/b'; back shows A, then Home.
    for (final MapEntry(key: name, value: call) in calls.entries) {
      testWidgets(
        'Back after $name skips the page it took off',
        (tester) async {
          final router = buildWalkRouter();
          await pumpRouterAppWithConfig(tester, router);
          final home = browserEntryIndex()!;
          for (final page in ['ARoute', 'BRoute', 'CRoute']) {
            unawaited(router.push(NamedRoute(page)));
            await tester.pumpAndSettle();
          }

          call(router);
          await tester.pumpAndSettle();
          await expectBrowserEntry(home + 2);
          await expectBrowserUrl('/b');

          await expectBrowserBackWalk(tester, router, [
            ('ARoute', '/a'),
            ('HomeRoute', '/'),
          ]);
        },
        skip: !kIsWeb,
      );
    }
  });
}
