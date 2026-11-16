import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link into a page that is not open, whose nested router's guard says no,
// leaves the user where they were: the page goes back off, the dialog they
// had open stays, and the url is that of the page on screen. While the
// guard decides, the dialog stays open under the page.
// Native behavior this holds to: Android's conditional navigation pops back
// from a destination whose check fails; on the web a canceled navigation
// leaves the document on screen.
// Headless test:
// auto_route/test/guards/rejected_nested_guard_takes_page_back_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => Scaffold(
    body: SafeArea(child: Center(child: Text(name))),
  );

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

  group('rejected nested guard takes page back', () {
    // Steps: open Home and a dialog on it. The platform hands the running
    // app the link /mail/77; Mail is not open. The guard of message 77 asks
    // the test, which says no.
    // Was: Mail stayed open on its inbox, at /mail, and the dialog was gone.
    // Should: Home and its dialog, at the root url.
    testWidgets('A nested guard saying no keeps Home and its dialog', (
      tester,
    ) async {
      final answer = Completer<bool>();
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
                  AutoRouteGuard.simple(
                    (resolver, _) async => await answer.future
                        ? resolver.next()
                        : resolver.reject(),
                  ),
                ],
                builder: (_, data) =>
                    page('Mail ${data.params.getString('id')}'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Draft')),
      );
      await tester.pumpAndSettle();

      await openLink(tester, '/mail/77');

      expect(
        find.text('Draft', skipOffstage: false),
        findsOneWidget,
        reason: 'the dialog is open while the guard decides',
      );

      answer.complete(false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('Draft'), findsOneWidget);
      expect(router.currentUrl, '/');
      await expectBrowserUrl('/');
    });
  });
}
