import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// After a link a guard rejects, the running app's url names the page on
// screen, as a refused navigation changes nothing.
// Headless test: auto_route/test/guards/rejected_link_url_running_test.dart
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

  group('rejected link url running', () {
    // Steps: open Home and push Details, then the platform hands the running
    // app the link /secret, whose guard rejects it.
    // Was: Details showed while the app's url was /secret.
    // Should: the url stays /details.
    testWidgets(
      'The url names the page on screen after a rejected link',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('DetailsRoute', '/details'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => page(name),
              ),
            NamedRouteDef(
              name: 'SecretRoute',
              path: '/secret',
              guards: [
                AutoRouteGuard.simple((resolver, _) => resolver.reject()),
              ],
              builder: (_, _) => page('SecretRoute'),
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('DetailsRoute')));
        await tester.pumpAndSettle();
        expect(router.isPathActive('/details'), isTrue);

        await openLink(tester, '/secret');

        expect(find.text('DetailsRoute'), findsOneWidget);
        expect(find.text('SecretRoute'), findsNothing);
        expect(router.currentUrl, '/details');
        expect(router.isPathActive('/secret'), isFalse);
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it. The web case, browser forward to
      // an entry whose guard now rejects, is in
      // auto_route/test/web/rejected_link_url_web_test.dart.
      skip: kIsWeb,
    );
  });
}
