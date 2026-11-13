import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// An app started at a link with a percent-escape that is not valid UTF-8,
// such as '/books/%FF' or '/search?q=%FF', shows a page.
// Steps: start the app at the link as the platform does on a cold start. The
// routes end with a catch-all page.
// Was: no page at all. Uri.decodeComponent on each path segment and
// Uri.queryParametersAll threw a FormatException ("Invalid UTF-8 byte") out
// of parseRouteInformation, so the Router never got a route, not even '*'.
// Native behavior this holds to: the URL standard reads such escapes with a
// lossy UTF-8 decode that gives U+FFFD and never fails, so a browser opens
// the url; Flutter's Navigator never leaves an app without a page for an
// initial route it can't show, as Navigator.defaultGenerateInitialRoutes
// shows.
//
// On the web the web history's url comparison, _isSameUrl in
// navigation_history_impl.dart, also read the url with Uri.decodeFull, which
// threw on the same bytes; it now reads them as U+FFFD too.
//
// Not covered: the same link handed to a running app. There Flutter's own
// WidgetsBindingObserver.didPushRouteInformation decodes the url first and
// reports the FormatException itself.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'SearchRoute',
      path: '/search',
      builder: (_, _) => const Text('SearchRoute'),
    ),
    NamedRouteDef(
      name: 'BookRoute',
      path: '/books/:id',
      builder: (_, _) => const Text('BookRoute'),
    ),
    NamedRouteDef(
      name: 'NotFoundRoute',
      path: '*',
      builder: (_, _) => const Text('NotFoundRoute'),
    ),
  ],
);

void main() {
  test('Dart reads these links without error', () {
    expect(Uri.parse('/books/%FF').path, '/books/%FF');
    expect(Uri.parse('/search?q=%FF').query, 'q=%FF');
  });

  test('Such bytes read as U+FFFD, as the URL standard reads them', () {
    final router = _router();
    final book = router.matcher.match('/books/%FF')?.lastOrNull;
    expect((book?.name, book?.params.getString('id')), ('BookRoute', '\uFFFD'));
    final search = router.matcher.match('/search?q=%FF&q=a')?.lastOrNull;
    expect(search?.queryParams.rawMap, {
      'q': ['\uFFFD', 'a'],
    });
  });

  // Steps: start the app at the link as the platform does on a cold start. The
  // routes end with a catch-all page.
  // Should: the app shows a page.
  for (final link in ['/books/%FF', '/search?q=%FF', '/nowhere/%FF']) {
    testWidgets('An app started at $link shows a page', (tester) async {
      final router = _router();
      final provider = PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(uri: Uri.parse(link)),
      );
      addTearDown(router.dispose);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routeInformationProvider: provider,
          routeInformationParser: router.defaultRouteParser(),
          routerDelegate: router.delegate(),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.name), isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
