// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// On the web, an app that swaps between two routers, as one for signed-out
// users and one for signed-in users, shows in the address bar the url of
// the router on screen. Each router has a web history of its own, and the
// browser has one history: the router a Router shows writes it, and starts
// from the entry the browser stands on when it is shown again.
//
// While the web history was becoming the browser's one writer, the router
// shown again took the browser to hold what it had written before the
// swap, and wrote nothing: the address bar kept the other router's url.
//
// Native behavior this holds to: the HTML History API, where the address
// bar shows the url of the entry the document last wrote; and Flutter's
// Router, which reports the route of the delegate it shows.
// Headless test off the web: test/simple_router/switch_routers_test.dart
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: open the app signed out, sign in, push a page, sign out.
  testWidgets('On web, swapping the router on sign-in and sign-out shows '
      'the url of the router on screen', (tester) async {
    final signedOut = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'LoginRoute',
          path: '/login',
          initial: true,
          builder: (_, _) => const Text('login'),
        ),
        RedirectRoute(path: '*', redirectTo: '/login'),
      ],
    );
    final signedIn = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          initial: true,
          builder: (_, _) => const Text('home'),
        ),
        NamedRouteDef(
          name: 'ARoute',
          path: '/a',
          builder: (_, _) => const Text('a'),
        ),
        RedirectRoute(path: '*', redirectTo: '/'),
      ],
    );
    addTearDown(signedOut.dispose);
    addTearDown(signedIn.dispose);
    final isSignedIn = ValueNotifier(false);
    addTearDown(isSignedIn.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: isSignedIn,
        builder: (_, isSignedInNow, _) {
          final router = isSignedInNow ? signedIn : signedOut;
          return MaterialApp.router(
            routerDelegate: router.delegate(),
            routeInformationParser: router.defaultRouteParser(),
          );
        },
      ),
    );
    await settleBrowser(tester);
    expect((browserSerialCount, browserPath), (0, '/login'));

    isSignedIn.value = true;
    await settleBrowser(tester);
    expect(find.text('home'), findsOneWidget);
    expect((browserSerialCount, browserPath), (0, '/'));

    unawaited(signedIn.push(const NamedRoute('ARoute')));
    await settleBrowser(tester);
    expect((browserSerialCount, browserPath), (1, '/a'));

    isSignedIn.value = false;
    await settleBrowser(tester);
    expect(find.text('login'), findsOneWidget);
    expect((browserSerialCount, browserPath), (1, '/login'));
  });
}
