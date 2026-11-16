import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, an app opened at a url the router writes otherwise, such as
// one with a trailing slash or one a route redirects, has one browser entry,
// holding the url as the router writes it: the first press of the back
// button leaves the app.
// Headless test: auto_route/test/web/opened_at_one_entry_web_test.dart.
//
// Native behavior this holds to: on the web a url the user did not navigate
// to takes the place of the current entry, as an HTTP redirect and
// Location.replace do. Web only: off the web there is no address bar.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('opened at a rewritten url', () {
    // Steps: open the app at the url.
    // Should: A shows, the address bar holds '/a', and the browser is on the
    // entry it was opened on.
    for (final url in ['/a/', '/old']) {
      testWidgets(
        'An app opened at $url has one entry, with /a',
        (tester) async {
          final entryBefore = browserEntryIndex() ?? 0;
          final router = RootStackRouter.build(
            routes: [
              for (final (name, path) in [('HomeRoute', '/'), ('ARoute', '/a')])
                NamedRouteDef(
                  name: name,
                  path: path,
                  builder: (_, _) => Text(name),
                ),
              RedirectRoute(path: '/old', redirectTo: '/a'),
            ],
          );
          await pumpAppAtDeepLink(
            tester,
            url,
            // Made inside the app, so the config reads the link.
            Builder(
              builder: (_) => MaterialApp.router(routerConfig: router.config()),
            ),
          );

          expect(find.text('ARoute'), findsOneWidget);
          await expectBrowserUrl('/a');
          await expectAppWroteDeepLinkEntry(entryBefore);
        },
        skip: !kIsWeb,
      );
    }
  });
}
