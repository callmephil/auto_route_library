import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// DeepLink.prefixStripper cuts its prefix from the link's path alone, so a
// link whose host starts with the prefix's text opens its page.
// Headless test: auto_route/test/prefix_stripper_test.dart
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

  group('prefix stripper', () {
    // Steps: the app runs on '/' with DeepLink.prefixStripper('/app'); the
    // platform hands it https://app.example.com/app/books/1, as an App Link
    // or a universal link does.
    // Was: the text '/app' was cut out of the host, and no page opened.
    // Should: the book page opens.
    testWidgets(
      'A link whose host starts with the prefix opens its page',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => const Scaffold(
                body: SafeArea(child: Center(child: Text('HomeRoute'))),
              ),
            ),
            NamedRouteDef(
              name: 'BookRoute',
              path: '/books/:id',
              builder: (_, data) => Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Text('Book ${data.params.getString('id')}'),
                  ),
                ),
              ),
            ),
          ],
        );
        await pumpRouterConfigApp(
          tester,
          router.config(deepLinkTransformer: DeepLink.prefixStripper('/app')),
        );

        await openLink(tester, 'https://app.example.com/app/books/1');

        expect(find.text('Book 1'), findsOneWidget);
        expect(router.topRoute.name, 'BookRoute');
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );
  });
}
