import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link that closes pages on its way into a page that was not open, whose
// nested guard says no, leaves those pages open: on Home with A over it, a
// link to message 13 of Mail brings Home below Mail, and A stays.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document and its url on screen; Android's conditional navigation
// pops back to the start destination when the check fails.
// Headless test:
// auto_route/test/guards/rejected_nested_guard_keeps_pages_closing_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Hands [location] to the running app the way the engine does when the
  // platform opens a link.
  Future<void> openLink(WidgetTester tester, String location) async {
    const codec = JSONMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': location,
          'state': null,
        }),
      ),
      null,
    );
    await tester.pumpAndSettle();
  }

  group('rejected nested guard keeps pages closing', () {
    Widget page(String name) => Scaffold(
      body: SafeArea(child: Center(child: Text(name))),
    );

    // Steps: Home, then A pushed over it. The platform hands the app the
    // link /mail/13, which brings Home below Mail; the guard of message 13
    // says no.
    // Was: Home and Mail on its inbox; A was closed.
    // Should: Home and A, at the url of A, with A's caller still waiting.
    testWidgets('A link whose nested guard says no keeps A', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'ARoute',
            path: '/a',
            builder: (_, _) => page('ARoute'),
          ),
          NamedRouteDef.shell(
            name: 'MailRoute',
            path: '/mail',
            children: [
              NamedRouteDef(
                name: 'InboxRoute',
                path: '',
                builder: (_, _) => page('InboxRoute'),
              ),
              NamedRouteDef(
                name: 'MessageRoute',
                path: ':id',
                guards: [
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
                ],
                builder: (_, _) => page('MessageRoute'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: true),
      );
      Object? gotA = #waiting;
      router
          .push<Object?>(const NamedRoute('ARoute'))
          .then((result) => gotA = result)
          .ignore();
      await tester.pumpAndSettle();

      await openLink(tester, '/mail/13');

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ARoute']);
      expect(find.text('ARoute'), findsOneWidget);
      expect(router.currentUrl, '/a');
      await expectBrowserUrl('/a');
      expect(gotA, #waiting);
    });
  });
}
