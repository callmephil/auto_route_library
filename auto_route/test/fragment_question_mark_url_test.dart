import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A url whose fragment holds a '?' opens its page, from a link or a push.
// Steps: the app runs on '/'; the platform hands it '/books/a%20b#what?', or
// the app pushes the same page with the fragment 'what?'.
// Was: RangeError from UrlState.url, and no page: it took the first '?' of the
// whole url, the one inside the fragment, as the start of the query.
// Native behavior this holds to: RFC 3986 section 3.5 allows '?' in a
// fragment, and a browser's URL parser, like Dart's Uri.parse, reads
// '/books/a%20b#what?' as the path '/books/a%20b', no query and the fragment
// 'what?'.
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
      builder: (_, data) =>
          Text('Book ${data.params.getString('id')} #${data.fragment}'),
    ),
  ],
);

void main() {
  test('UrlState.url reads a url whose fragment holds a "?"', () {
    final uri = Uri.parse('/books/a%20b#what?');
    // What Dart's Uri makes of it: no query, the '?' is in the fragment.
    expect(
      (uri.path, uri.hasQuery, uri.fragment),
      ('/books/a%20b', false, 'what?'),
    );
    expect(UrlState(uri, const []).url, '/books/a b#what?');
  });

  // Steps: the app runs on '/'; the platform hands it '/books/a%20b#what?'.
  // Should: the book page opens, as it does for '/books/a%20b#what'.
  testWidgets('A link whose fragment holds a "?" opens its page', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await _sendPlatformLink(tester, '/books/a%20b#what?');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Book a b #what?'), findsOneWidget);
    expect(router.currentUrl, '/books/a b#what?');
  });

  // Steps: push the same page in code.
  testWidgets('A route pushed with a "?" in its fragment opens its page', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(
      router.push(
        const NamedRoute('BookRoute', params: {'id': 'a b'}, fragment: 'what?'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Book a b #what?'), findsOneWidget);
    expect(router.currentUrl, '/books/a b#what?');
  });
}

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
