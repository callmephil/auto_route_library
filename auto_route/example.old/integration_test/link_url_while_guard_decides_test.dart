import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// callmephil/auto_route_library#9: off the web, while the guard of a link
// decides, the app's url names the page on screen, not the link's page.
// Steps: Home shows at '/'. The platform hands the running app the link
// '/secret', whose guard waits for the test. The test reads the url, then
// the guard says yes or no.
// Was: the url named '/secret' while Home showed.
// Should: '/' while the guard waits; '/secret' once Secret shows after a
// yes; '/' still after a no.
// Off the web only: on the web the browser shows a link's url at once.
// Native behavior this holds to: Android's NavController names the
// destination on top of its back stack, and a navigation that does not
// happen changes nothing.
// Headless test: auto_route/test/guards/link_url_while_guard_decides_test.dart
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

  group('link url while guard decides', () {
    for (final isYes in [false, true]) {
      testWidgets(
        'The url names Home while the guard decides, then '
        '${isYes ? 'Secret after a yes' : 'Home after a no'}',
        (tester) async {
          final answer = Completer<bool>();
          final router = RootStackRouter.build(
            routes: [
              NamedRouteDef(
                name: 'HomeRoute',
                path: '/',
                builder: (_, _) => page('Home'),
              ),
              NamedRouteDef(
                name: 'SecretRoute',
                path: '/secret',
                guards: [
                  AutoRouteGuard.simple(
                    (resolver, _) async => await answer.future
                        ? resolver.next()
                        : resolver.reject(),
                  ),
                ],
                builder: (_, _) => page('Secret'),
              ),
            ],
          );
          await pumpRouterConfigApp(tester, router.config());

          await openLink(tester, '/secret');

          expect(find.text('Home'), findsOneWidget);
          expect(router.currentUrl, '/');

          answer.complete(isYes);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text(isYes ? 'Secret' : 'Home'), findsOneWidget);
          expect(router.currentUrl, isYes ? '/secret' : '/');
        },
        skip: kIsWeb,
      );
    }
  });
}
