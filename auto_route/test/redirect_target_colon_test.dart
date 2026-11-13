import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A RedirectRoute among a route's children whose redirectTo starts with a
// path param opens its target when the param's value holds a ':'.
// Steps: '/slots' has the children ':time' (SlotRoute) and a RedirectRoute
// from 'at/:time' to ':time'. The app runs on '/', and the platform hands it
// /slots/at/12:30, or /slots/at/user:5.
// Was: /slots/at/12:30 threw "FormatException: Scheme not starting with
// alphabetic character" out of the route parser, so the link opened nothing,
// and /slots/at/user:5 opened the slot "5": the matcher read the redirect's
// target with Uri.parse, which takes the text before the ':' as a scheme.
// Found by the second audit (U2-5); the same trap was closed for pushPath.
// Native behavior this holds to: RFC 3986 section 4.2 names the trap for a
// relative reference; a redirect's target is a path, as pushPath's is, so the
// slot opens as its own url /slots/12:30 does.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
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
          builder: (_, data) => Text('Slot ${data.params.getString('time')}'),
        ),
        RedirectRoute(path: 'at/:time', redirectTo: ':time'),
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
  for (final (link, page) in [
    // Controls.
    ('/slots/at/9', 'Slot 9'),
    ('/slots/12:30', 'Slot 12:30'),
    ('/slots/user:5', 'Slot user:5'),
    // The redirect, with a ':' in the value.
    ('/slots/at/12:30', 'Slot 12:30'),
    ('/slots/at/user:5', 'Slot user:5'),
  ]) {
    testWidgets('The link $link opens "$page"', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: false),
      );
      await _sendPlatformLink(tester, link);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .toList();
      expect(shown, [page], reason: 'the link $link shows $shown');
    });
  }
}
