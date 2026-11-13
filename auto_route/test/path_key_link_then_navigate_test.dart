import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// With usesPathAsKey, a page a link opened is not pushed a second time when
// the app navigates to it.
// Steps: '/slots' has the child ':time', which uses its path as key, as the
// README's "One page per path" shows. The platform hands the app
// /slots/user:5. Then the app navigates the nested router to the slot
// 'user:5', the page that is open. At the top level, the link
// /users/test%40example.com, as JavaScript's encodeURIComponent writes an
// e-mail address, then navigate to the user 'test@example.com'.
// Was: the stack held the page twice, and back from the second showed the
// same page again. The key of the link's page was the link's own spelling
// ('user%3A5', '%40'), the key of the route's page the text the route
// expands ('user:5', '@'). Found by the second audit (U2-7).
// Decided: one spelling for the key however the page was opened, nested and
// top-level alike, since the router reads the same param from both.
// The controls kept one page already: ids without such characters, a space,
// which both sides write as %20, and 12:30 in the nested router, which Dart
// doesn't escape.
// Native behavior this holds to: Flutter's Navigator decides by
// Page.canUpdate, which compares the keys it is given, so the key must not
// depend on how the same path was written; README, "One page per path": with
// usesPathAsKey "navigate back to book 1 pops to it".
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'UserRoute',
      path: '/users/:id',
      usesPathAsKey: true,
      builder: (_, data) => Text('User ${data.params.getString('id')}'),
    ),
    NamedRouteDef(
      name: 'SlotsRoute',
      path: '/slots',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'SlotListRoute',
          path: '',
          builder: (_, _) => const Text('SlotListRoute'),
        ),
        NamedRouteDef(
          name: 'SlotRoute',
          path: ':time',
          usesPathAsKey: true,
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

// The names of the pages on [router]'s stack, bottom first.
String _pages(StackRouter? router) =>
    router?.stackData.map((data) => data.name).join(' ') ?? '';

void main() {
  group('A nested page keyed by its path:', () {
    for (final time in ['9', '12:30', 'user:5']) {
      testWidgets('the link /slots/$time, then navigate to the slot "$time", '
          'keeps one slot page', (tester) async {
        final router = _router();
        await pumpRouterConfigApp(tester, router.config());
        await _sendPlatformLink(tester, '/slots/$time');
        await tester.pumpAndSettle();
        final nested = router.innerRouterOf<StackRouter>('SlotsRoute');
        final before = _pages(nested);

        unawaited(
          nested?.navigate(NamedRoute('SlotRoute', params: {'time': time})),
        );
        await tester.pumpAndSettle();
        // The pages under the slot differ by platform: off the web a link
        // also opens the slot list below it.
        expect(
          (_pages(nested), find.text('Slot $time').evaluate().length),
          (before, 1),
        );
      });
    }
  });

  group('A top-level page keyed by its path:', () {
    for (final (link, id) in [
      ('/users/ab', 'ab'),
      ('/users/a%20b', 'a b'),
      ('/users/test%40example.com', 'test@example.com'),
      ('/users/12%3A30', '12:30'),
    ]) {
      testWidgets('the link $link, then navigate to the user "$id", keeps one '
          'user page', (tester) async {
        final router = _router();
        await pumpRouterConfigApp(tester, router.config());
        await _sendPlatformLink(tester, link);
        await tester.pumpAndSettle();
        final before = _pages(router);

        unawaited(router.navigate(NamedRoute('UserRoute', params: {'id': id})));
        await tester.pumpAndSettle();
        expect(
          (_pages(router), find.text('User $id').evaluate().length),
          (before, 1),
        );
      });
    }
  });
}
