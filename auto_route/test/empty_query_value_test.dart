import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// An empty query value reads as absent, however the page was opened: `?b=`,
// a bare `?c`, and an empty entry of a repeated key such as `?tag=a&tag=`.
// Steps: the page /books/:id reads its query params from the scoped
// RouteData, as the README shows (`context.routeData.queryParams`). The
// platform hands the app /books/1?a=1&b=&c. Then the url the router reports
// for that page is reloaded. Also: the route is pushed in code with an empty
// text for a query param.
// Was: at the link the page read `b: ''` and `c: ''`, the router reported
// /books/1?a=1, and a reload of that url read neither, so a page showed
// something else after a reload or a shared link. The url dropped an empty
// value, the reader kept it. Inside a repeated key the empty entry was kept
// and written as a bare key. Found by the second audit's urls reader
// ("Doubts about a decision").
// Decided by Phil on 2026-11-13: "?b= means nothing", so the router ignores
// it rather than throw, since a throw would crash the app on a url a user
// types. A page no longer reads an empty text for such a key.
// Native behavior: none to hold to. Browsers keep `?b=`
// (URLSearchParams.has('b') is true) and Dart's Uri.queryParameters keeps the
// key; the router deliberately differs from both, on Phil's decision.
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
      builder: (_, data) => Text('Query ${data.queryParams.rawMap}'),
    ),
  ],
);

// Hands [location] to the running app the way the engine does when the
// platform opens a link.
Future<void> _sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

// The query params the book page on screen shows.
String _shownQuery(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining('Query ')).data ?? '';

// What the book page shows when a fresh app opens [url], as a reload does.
Future<String> _shownAfterReload(WidgetTester tester, String url) async {
  final router = _router();
  addTearDown(router.dispose);
  await pumpRouterConfigApp(tester, router.config());
  await _sendPlatformLink(tester, url);
  await tester.pumpAndSettle();
  return _shownQuery(tester);
}

void main() {
  for (final (link, shown, url) in [
    ('/books/1?a=1', 'Query {a: 1}', '/books/1?a=1'),
    ('/books/1?a=1&b=&c', 'Query {a: 1}', '/books/1?a=1'),
    ('/books/1?tag=a&tag=', 'Query {tag: a}', '/books/1?tag=a'),
    (
      '/books/1?tag=a&tag=&tag=b',
      'Query {tag: [a, b]}',
      '/books/1?tag=a&tag=b',
    ),
    ('/books/1?tag=&tag=', 'Query {}', '/books/1'),
  ]) {
    testWidgets('The link $link shows the same query before and after a '
        'reload', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      await _sendPlatformLink(tester, link);
      await tester.pumpAndSettle();
      final atLink = _shownQuery(tester);
      final reported = router.currentUrl;

      expect(
        (atLink, reported, await _shownAfterReload(tester, reported)),
        (shown, url, shown),
      );
    });
  }

  for (final (query, shown, url) in [
    (<String, Object?>{'a': '1', 'b': ''}, 'Query {a: 1}', '/books/1?a=1'),
    (
      <String, Object?>{
        'tag': ['a', ''],
      },
      'Query {tag: [a]}',
      '/books/1?tag=a',
    ),
  ]) {
    testWidgets('Pushed in code with the query $query, the page shows '
        '"$shown" and so does a reload of its url', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      unawaited(
        router.push(
          NamedRoute(
            'BookRoute',
            params: const {'id': '1'},
            queryParams: query,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final atPush = _shownQuery(tester);
      final reported = router.currentUrl;

      expect((atPush, reported), (shown, url));
      // A list of one reads back from the url as its one value.
      expect(
        await _shownAfterReload(tester, reported),
        shown.replaceAll('[a]', 'a'),
      );
    });
  }
}
