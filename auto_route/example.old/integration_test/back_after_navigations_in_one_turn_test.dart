import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, navigations the app makes in one turn leave the browser as
// the same calls a frame apart: each page still open has an entry, and the
// back button closes the page on top, never showing one the app closed.
// Headless tests: auto_route/test/web/native_walk_web_test.dart and
// auto_route/test/browser_navigation_history_test.dart.
//
// Native behavior this holds to: Flutter's Navigator under the system back,
// which closes the page on top; a page the app closed never comes back.
// Web only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigations in one turn', () {
    // Steps: on Home, push A and B a frame apart. Then, in one turn, pop
    // twice, push C and D, and pop once more. Press the browser's back
    // button.
    // Should: C shows at '/c', one entry over the entry of Home, and back
    // shows Home.
    testWidgets(
      'Back after pops and pushes in one turn shows the page under, never a '
      'closed one',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex()!;
        for (final name in ['ARoute', 'BRoute']) {
          unawaited(router.push(NamedRoute(name)));
          await tester.pumpAndSettle();
        }

        for (var i = 0; i < 2; i++) {
          router.pop();
        }
        unawaited(router.push(const NamedRoute('CRoute')));
        unawaited(router.push(const NamedRoute('DRoute')));
        router.pop();
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/c');

        await expectBrowserBackWalk(tester, router, [('HomeRoute', '/')]);
      },
      skip: !kIsWeb,
    );
  });
}
