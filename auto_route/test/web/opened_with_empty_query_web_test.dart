// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// On the web, an app opened at a url the router writes otherwise, such as
// /a?b=, whose empty query value the router leaves out, keeps one browser
// entry: the url without the empty value takes the place of the entry the
// app was opened at. It was added as a second entry, so the browser's back
// button went back to the url as typed.
//
// Native behavior this holds to: on the web a url change the user did not
// navigate to replaces the current entry, as a redirect does
// (MDN, Location.replace).
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: open the app at /a?b=.
  testWidgets('On web, an app opened at /a?b= keeps one browser entry', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [('HomeRoute', '/'), ('ARoute', '/a')])
          NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
      ],
    );
    addTearDown(router.dispose);
    openBrowserAt(tester, '/a?b=');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(routerConfig: router.config()),
    );
    await settleBrowser(tester);
    expect(
      (router.currentUrl, browserPath, browserSerialCount),
      ('/a', '/a', 0),
    );
  });
}
