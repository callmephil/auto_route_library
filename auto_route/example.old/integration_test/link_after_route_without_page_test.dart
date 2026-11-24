import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// The launch page rule ends at the first route that the Router hands over,
// also at a route that opens no page (callmephil/auto_route_library#46).
// Before, a link that no route matches left the rule on, so the next link
// took the place of Home, and the system back left the app.
// Headless test: auto_route/test/link_after_route_without_page_test.dart.
//
// Native behavior this holds to: a link to an app that is open adds its page
// over the page on screen, as Flutter's Navigator.push does; only the link of
// a cold start has nothing under its page. Off the web only: a browser opens
// the app at its url, so the rule is never on there.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a link after a route that opens no page', () {
    // Steps: with includePrefixMatches: false, the app opens at / and shows
    // Home. The platform hands it the link /nope, which no route matches,
    // then the link /b. Then the system back.
    // Was: /b took the place of Home, and the system back left the app.
    // Should: /b opens over Home, and the system back shows Home.
    testWidgets(
      'off the web, the link /b after /nope opens over Home',
      (tester) async {
        final router = buildWalkRouter();
        await _open(tester, router);

        await tester.binding.handlePushRoute('/nope');
        await tester.pumpAndSettle();
        expectTopPage(router, 'HomeRoute');
        await tester.binding.handlePushRoute('/b');
        await tester.pumpAndSettle();
        expect(router.stack.map((page) => page.name), ['HomeRoute', 'BRoute']);

        await systemBack(tester);
        expectTopPage(router, 'HomeRoute');
      },
      // A browser opens the app at its url, so the rule is never on there.
      skip: kIsWeb,
    );
  });
}

// Opens the app at / with prefix matches off, as on the web by default.
Future<void> _open(WidgetTester tester, RootStackRouter router) =>
    pumpRouterConfigApp(
      tester,
      router.config(
        includePrefixMatches: false,
        deepLinkBuilder: (link) => link.initial ? DeepLink.defaultPath : link,
      ),
    );
