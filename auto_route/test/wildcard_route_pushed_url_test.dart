import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// The app's '*' not-found page, opened in code, reports the url '/*'.
// Steps: the README's not-found page, AutoRoute(path: '*'), as the last
// route. The app shows /books/1. Open the not-found page in code, as an app
// does when the book doesn't exist: `router.replace(UnknownRoute())`.
// Was: router.currentUrl and currentPath were '*', a relative url, and the
// router reported it to the platform: the url was joined from the paths of
// the pages, and the top-level '*' page's path has no '/'. Flutter's
// PathUrlStrategy asserts on it in a debug build; in a release build the
// browser resolved '*' against /books/1, and a reload of /books/* opened the
// book page with the id '*'. Found by the second audit (U2-6).
// Decided: '/*', as a '*' page under '/shell' already reports '/shell/*': the
// url opens the page it names.
// Native behavior this holds to: flutter_web_plugins' PathUrlStrategy,
// prepareExternalUrl, holds that every route name starts with '/' since the
// browser's pathname always does; a relative reference resolves against the
// current url (RFC 3986 section 5.2).
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'BookRoute',
      path: '/books/:id',
      builder: (_, data) => Text('Book ${data.params.getString('id')}'),
    ),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'ShellHomeRoute',
          path: '',
          builder: (_, _) => const Text('ShellHomeRoute'),
        ),
        NamedRouteDef(
          name: 'ShellUnknownRoute',
          path: '*',
          builder: (_, _) => const Text('ShellUnknownRoute'),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'UnknownRoute',
      path: '*',
      builder: (_, _) => const Text('UnknownRoute'),
    ),
  ],
);

// The top page a reload of [url] opens.
String? _pageAt(String url) {
  final router = _router();
  addTearDown(router.dispose);
  return router.matcher.match(url)?.lastOrNull?.flattened.lastOrNull?.name;
}

void main() {
  testWidgets("Control: a nested '*' page opened in code has a url from the "
      'root that opens it again', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute(
          'ShellRoute',
          children: [NamedRoute('ShellUnknownRoute')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ShellUnknownRoute'), findsOneWidget);
    expect(router.currentPath, startsWith('/'));
    expect(_pageAt(router.currentUrl), 'ShellUnknownRoute');
  });

  testWidgets("The '*' page opened in code reports a url from the root", (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('BookRoute', params: {'id': '1'})));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/books/1');

    unawaited(router.replace(const NamedRoute('UnknownRoute')));
    await tester.pumpAndSettle();
    expect(find.text('UnknownRoute'), findsOneWidget);

    // What the router hands the platform for the address bar.
    final reported = router
        .defaultRouteParser()
        .restoreRouteInformation(router.urlState)
        .uri;
    expect(
      reported.path,
      startsWith('/'),
      reason: 'the url reported for the not-found page is "$reported"',
    );
  });

  testWidgets("The url the browser shows for the '*' page opens it again", (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('BookRoute', params: {'id': '1'})));
    await tester.pumpAndSettle();
    final shown = Uri.parse('https://example.com${router.currentUrl}');

    unawaited(router.replace(const NamedRoute('UnknownRoute')));
    await tester.pumpAndSettle();
    final reported = router
        .defaultRouteParser()
        .restoreRouteInformation(router.urlState)
        .uri;
    // history.pushState resolves the url it is given against the document's.
    final inAddressBar = shown.resolveUri(reported);
    expect(
      _pageAt(inAddressBar.path),
      'UnknownRoute',
      reason: 'the address bar holds ${inAddressBar.path}',
    );
  });
}
