// Off the web only: on the web the history is the browser's.
@TestOn('vm')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Off the web, a link whose path the router writes differently than the link
// has it opens its page with a history entry of its own, so router.back()
// returns to the page before. It hits a link with a trailing or doubled
// slash, one a RedirectRoute sends on, one that DeepLink.prefixStripper or
// any transformer changes, and a link to a nested page whose segment the
// matcher writes again ('user:5' as 'user%3A5', 'a%40b' as 'a@b').
// AutoRouterDelegate marked the url for replace whenever the link's own path
// differed from the path of its pages, and the native history then dropped
// its last entry, the page before: off the web the link never had one. The
// replace is right on the web only, where the browser made an entry for the
// link.
//
// Native behavior this holds to: a link is a navigation, whatever was
// rewritten in its url. Android puts the activity or destination a deep link
// opens over the back stack; a browser that follows a redirect still adds one
// history entry for the navigation (HTML, "URL and history update steps").
//
// Steps: the app runs on '/'; the platform hands it a link; call back().
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
    RedirectRoute(path: '/b/:id', redirectTo: '/books/:id'),
    NamedRouteDef(
      name: 'SlotsRoute',
      path: '/slots',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'SlotRoute',
          path: ':time',
          builder: (_, data) => Text('Slot ${data.params.getString('time')}'),
        ),
      ],
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

void main() {
  for (final (link, page, usesTransformer) in [
    // Links whose path the router writes as they have it.
    ('/books/1', 'Book 1', false),
    ('/slots/9', 'Slot 9', false),
    ('/books/1', 'Book 1', true),
    // Links whose path the router writes differently.
    ('/books/1/', 'Book 1', false),
    ('/books//1', 'Book 1', false),
    ('/b/1', 'Book 1', false),
    ('/app/books/1', 'Book 1', true),
    ('/slots/user:5', 'Slot user:5', false),
    ('/slots/a%40b', 'Slot a@b', false),
  ]) {
    testWidgets('Off the web, the link $link'
        '${usesTransformer ? ' with a prefix stripper' : ''} gets a history '
        'entry of its own, so back() leaves it', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(
          deepLinkTransformer: usesTransformer
              ? DeepLink.prefixStripper('/app')
              : null,
        ),
      );
      final lengthBefore = router.navigationHistory.length;

      await _sendPlatformLink(tester, link);
      await tester.pumpAndSettle();
      // The page, the stack under it, and the history's length.
      final opened = (
        find.text(page).evaluate().length,
        router.stack.map((p) => p.name).join(' '),
        router.navigationHistory.length,
      );
      router.back();
      await tester.pumpAndSettle();
      expect(
        (lengthBefore, opened),
        (
          1,
          (
            1,
            'HomeRoute ${page.startsWith('Book') ? 'BookRoute' : 'SlotsRoute'}',
            2,
          ),
        ),
      );
      expectCurrentPage(router, 'HomeRoute');
    });
  }
}
