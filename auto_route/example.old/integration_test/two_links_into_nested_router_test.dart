import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Of two links into a nested router, the one handed over last stays on
// screen when the guard of the first answers later.
// Headless test: auto_route/test/nested_router/two_links_into_nested_router_test.dart
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

  group('two links into nested router', () {
    // Steps: the app shows message 42 in the nested router of Mail. The
    // platform hands it a link to message 13, whose guard waits until the
    // test answers, then a link to message 14; then the guard of 13 answers
    // yes.
    // Was: message 13 landed over 14 as a second page with one key, and the
    // Navigator's check failed.
    // Should: message 14 stays on screen.
    testWidgets(
      'The later of two links into a nested router stays on screen',
      (tester) async {
        final answer13 = Completer<bool>();
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
            ),
            NamedRouteDef(
              name: 'MailRoute',
              path: '/mail',
              builder: (_, _) => const Scaffold(body: AutoRouter()),
              children: [
                NamedRouteDef(
                  name: 'MessageRoute',
                  path: ':id',
                  guards: [
                    AutoRouteGuard.simple((resolver, _) async {
                      if (resolver.route.params.getString('id') != '13') {
                        return resolver.next();
                      }
                      await answer13.future
                          ? resolver.next()
                          : resolver.reject();
                    }),
                  ],
                  builder: (_, data) => SafeArea(
                    child: Center(
                      child: Text('Mail ${data.params.getString('id')}'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        await openLink(tester, '/mail/42');
        expect(find.text('Mail 42'), findsOneWidget);

        await openLink(tester, '/mail/13');
        await openLink(tester, '/mail/14');
        answer13.complete(true);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Mail 14'), findsOneWidget);
        expect(find.text('Mail 13'), findsNothing);
        expect(router.currentUrl, '/mail/14');
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );
  });
}
