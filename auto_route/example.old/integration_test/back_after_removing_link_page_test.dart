import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// Off the web, router.back() never shows a page a platform link opened once
// the app has removed it.
// Headless test: auto_route/test/back_after_removing_link_page_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.removeRoute removes the
// route and disposes it (navigator.dart 2855-2867, Flutter 3.47.9), so no
// later pop returns to it. Off the web only: on the web, back() is the
// browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a page a link opened, then removed, off the web', () {
    // Steps: on Home, the platform hands the app the link /c. The app calls
    // removeLast, then back().
    // Was: back() opened C again.
    // Should: Home stays, and the history holds Home alone.
    testWidgets(
      'back() after the removal of the link page leaves Home',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterAppWithConfig(tester, router);
        await tester.binding.handlePushRoute('/c');
        await tester.pumpAndSettle();
        final onLink = router.current.name;

        router.removeLast();
        await tester.pumpAndSettle();
        router.back();
        await tester.pumpAndSettle();

        expect((onLink, router.current.name), ('CRoute', 'HomeRoute'));
        expect(find.text('CRoute'), findsNothing);
        expect(router.navigationHistory.length, 1);
      },
      skip: kIsWeb,
    );
  });
}
