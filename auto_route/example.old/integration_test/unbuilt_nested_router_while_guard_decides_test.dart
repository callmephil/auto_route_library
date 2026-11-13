import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The page a link brings below its own, in a nested router that is not built
// yet, shows while the guard of the link's page decides, as Flutter's
// Navigator shows the pages its list holds.
// Headless test:
// auto_route/test/guards/unbuilt_nested_router_while_guard_decides_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));

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

  group('unbuilt nested router while guard decides', () {
    // Steps: open Home. The platform hands the app the link to message 20
    // with the inbox below it. Mail is not open, and the guard of the
    // message waits for an answer. Then the guard lets the message in. Go
    // back.
    // Was: Mail showed nothing while the guard decided, though its router
    // held the inbox.
    // Should: the inbox shows meanwhile, then the message over it, and back
    // shows the inbox.
    testWidgets('The inbox shows while the guard of a linked message decides', (
      tester,
    ) async {
      final answer = Completer<void>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
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
                  AutoRouteGuard.simple((resolver, _) async {
                    await answer.future;
                    resolver.next();
                  }),
                ],
                builder: (_, data) =>
                    page('Mail ${data.params.getString('id')}'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: true),
      );

      await openLink(tester, '/mail/20');

      expect(tester.takeException(), isNull);
      int inboxesOnScreen() => find.text('InboxRoute').evaluate().length;
      final shownMeanwhile = inboxesOnScreen();

      answer.complete();
      await tester.pumpAndSettle();

      expect(find.text('Mail 20'), findsOneWidget);
      await expectBrowserUrl('/mail/20');

      await systemBack(tester);

      // The inbox was on screen while the guard decided, and is again.
      expect((shownMeanwhile, inboxesOnScreen()), (1, 1));
      expect(find.text('Mail 20'), findsNothing);
    });
  });
}
