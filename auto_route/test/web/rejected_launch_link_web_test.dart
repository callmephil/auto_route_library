// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// On the web, an app opened at a link that a guard rejects shows no page,
// and the address bar drops the link: it shows '/', on the entry the app
// was opened on, so a reload doesn't open the rejected link again.
//
// While the web history was becoming the browser's one writer, it found
// the Router through the app's navigator, which is not built while the app
// shows no page, so it wrote nothing and the link stayed in the address
// bar.
//
// Native behavior this holds to: a browser can't cancel a load the app has
// received, so the app writes what it shows over the entry it was opened
// on, as Location.replace does.
// Headless test off the web: test/guards/initial_reject_url_test.dart
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: open the app at '/protected', whose guard rejects it.
  testWidgets('On web, the address bar drops a launch link a guard '
      'rejected', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'ProtectedRoute',
          path: '/protected',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
          builder: (_, _) => const Text('ProtectedRoute'),
        ),
      ],
    );
    addTearDown(router.dispose);
    openBrowserAt(tester, '/protected');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(
        routerConfig: router.config(includePrefixMatches: false),
      ),
    );
    await settleBrowser(tester);

    expect(router.stack, isEmpty);
    expect(find.text('ProtectedRoute'), findsNothing);
    expect((browserSerialCount, browserPath), (0, '/'));
  });
}
