// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// On the web, an app opened at a url the router writes otherwise, such as
// '/a?b=' for '/a', one with a trailing slash or one a route redirects, has
// one browser entry, which holds the url as the router writes it. So has an
// app opened at a page whose guard shows a login page first, once the user
// has signed in.
//
// Before the web history became the browser's one writer, Flutter's Router
// wrote the first url after the first frame. It compared it with the url
// the browser was opened at, found another one and added an entry, so the
// first press of the back button seemed to do nothing. The guard's login
// page got an entry of its own under the page's.
//
// Native behavior this holds to: on the web a url the user did not navigate
// to takes the place of the current entry, as an HTTP redirect and
// Location.replace do, so the address the user came by is not on the way
// back.
var _isSignedIn = false;
NavigationResolver? _signingIn;

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('LoginRoute', '/login'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
    NamedRouteDef(
      name: 'AccountRoute',
      path: '/account',
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          if (_isSignedIn) return resolver.next();
          _signingIn = resolver;
          unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
        }),
      ],
      builder: (_, _) => const Text('AccountRoute'),
    ),
    RedirectRoute(path: '/old', redirectTo: '/a'),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(() async {
    await rewindBrowserHistory();
    _isSignedIn = false;
    _signingIn = null;
  });

  for (final usesOwnProvider in [true, false]) {
    final provider = usesOwnProvider
        ? "auto_route's own provider"
        : "Flutter's provider";

    // Opens the app the way a browser does at [url].
    Future<RootStackRouter> open(WidgetTester tester, String url) async {
      final router = _router();
      addTearDown(router.dispose);
      openBrowserAt(tester, url);
      await pumpAsRunApp(
        tester,
        usesOwnProvider
            ? MaterialApp.router(routerConfig: router.config())
            : MaterialApp.router(
                routerDelegate: router.delegate(),
                routeInformationParser: router.defaultRouteParser(),
              ),
      );
      await settleBrowser(tester);
      return router;
    }

    // Steps: open the app at the url.
    for (final (url, written) in [
      ('/a?b=', '/a'),
      ('/a/', '/a'),
      ('/old', '/a'),
      ('/a', '/a'),
    ]) {
      testWidgets('On web, with $provider, an app opened at $url has one '
          'browser entry, with $written', (tester) async {
        final first = browserSerialCount < 0 ? 0 : browserSerialCount;
        final router = await open(tester, url);

        expect(router.currentUrl, written);
        expect((browserSerialCount - first, browserPath), (0, written));
      });
    }

    // Steps: open the app at the guarded page, then sign in on the login
    // page its guard shows.
    testWidgets('On web, with $provider, an app opened at a page whose guard '
        'shows a login page has one browser entry, before and after the '
        'sign-in', (tester) async {
      final first = browserSerialCount < 0 ? 0 : browserSerialCount;
      final router = await open(tester, '/account');
      expect((browserSerialCount - first, browserPath), (0, '/login'));

      _isSignedIn = true;
      _signingIn?.next();
      await settleBrowser(tester);

      expect(router.stack.map((page) => page.name), ['AccountRoute']);
      expect((browserSerialCount - first, browserPath), (0, '/account'));
    });
  }
}
