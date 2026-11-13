// Off the web only: on the web the history is the browser's.
@TestOn('vm')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Off the web, a link with a percent-escape in its path, such as
// '/books/a%20b' or '/books/caf%C3%A9', that reaches the running app opens
// its page with a history entry of its own, as '/books/ab' does, so back()
// returns to the page before. It used to take the entry of the page before
// instead: the history had one entry, canNavigateBack was false and back()
// did nothing.
//
// Steps: the app runs on '/'; the platform hands it the link; call back().
//
// Native behavior this holds to: a link is a navigation like any other,
// whatever characters its url holds. Android puts the page a deep link opens
// over the task's back stack, and a browser adds one history entry for a
// navigation to '/books/a%20b' as for '/books/ab' (HTML, "URL and history
// update steps": a navigation pushes unless it is a replace). The README says
// of router.back(): "on Native it navigates you back to the previous
// location".
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
  for (final (link, id) in [
    ('/books/ab', 'ab'),
    ('/books/a%20b', 'a b'),
    ('/books/caf%C3%A9', 'café'),
  ]) {
    testWidgets('The link $link adds a history entry, so back() leaves it', (
      tester,
    ) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      expect(router.navigationHistory.length, 1);

      await _sendPlatformLink(tester, link);
      await tester.pumpAndSettle();
      expect(find.text('Book $id'), findsOneWidget);
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'BookRoute']);

      expect(router.navigationHistory.length, 2);
      expect(router.canNavigateBack, isTrue);
      router.back();
      await tester.pumpAndSettle();
      expectCurrentPage(router, 'HomeRoute');
    });
  }
}
