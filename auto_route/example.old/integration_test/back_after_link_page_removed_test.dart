import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, when the page that holds a link's browser entry is removed
// from under another page, the page under it that the link opened takes
// the entry over, so the back button still reaches it.
// Headless test: auto_route/test/web/link_page_removed_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator, where removeRoute
// leaves the routes below and above it, and the system back from C then
// shows A. Web only: off the web there is no browser back button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a page removed from under a link', () {
    // Steps: open the app at the link /b, which opens Home, A and B; push
    // C; remove B. Press the browser's back button.
    // Should: C shows at '/c' on the entry after the link's, and back shows
    // A at '/a' on the link's entry.
    testWidgets(
      'Back after the removal of the link page shows the page under it',
      (tester) async {
        final router = buildWalkRouter();
        final linkEntry = browserEntryIndex() ?? 0;
        // The config reads the platform's initial route when it is first
        // made, so it is made inside the app, after pumpAppAtDeepLink sets
        // the link, as runApp would find it.
        await pumpAppAtDeepLink(
          tester,
          '/b',
          Builder(
            builder: (_) => MaterialApp.router(
              routerConfig: router.config(
                deepLinkBuilder: (link) => link.path == '/b'
                    ? const DeepLink([
                        NamedRoute('HomeRoute'),
                        NamedRoute('ARoute'),
                        NamedRoute('BRoute'),
                      ])
                    : link,
              ),
            ),
          ),
        );
        // The browser entry counted from the link's, the url and the stack,
        // once the app is open, after the push of C and after the removal.
        String reading() =>
            '(${(browserEntryIndex() ?? 0) - linkEntry}, ${browserUrl()}, '
            '${router.stack.map((page) => page.name).join(' ')})';
        await SystemNavigator.selectMultiEntryHistory();
        final readings = [reading()];

        unawaited(router.push(const NamedRoute('CRoute')));
        await tester.pumpAndSettle();
        await SystemNavigator.selectMultiEntryHistory();
        readings.add(reading());

        router.removeWhere((route) => route.name == 'BRoute');
        await tester.pumpAndSettle();
        await expectBrowserUrl('/c');
        readings.add(reading());
        expect(readings, [
          '(0, /b, HomeRoute ARoute BRoute)',
          '(1, /c, HomeRoute ARoute BRoute CRoute)',
          '(1, /c, HomeRoute ARoute CRoute)',
        ]);

        await expectBrowserBackWalk(tester, router, [('ARoute', '/a')]);
      },
      skip: !kIsWeb,
    );
  });
}
