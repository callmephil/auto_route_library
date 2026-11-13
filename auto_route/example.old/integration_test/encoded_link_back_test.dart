import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, a link with a percent-escape in its path opens its page with
// a history entry of its own, so router.back() returns to the page before.
// Headless test: auto_route/test/encoded_link_history_entry_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('encoded link back', () {
    // Steps: open Home, then the platform hands the running app the link
    // /books/a%20b. Tap 'Back', which calls router.back().
    // Was: the link took Home's history entry, so 'Back' did nothing.
    // Should: Home shows again, as it does after the link /books/ab.
    // Native behavior: Android puts the page a deep link opens over the back
    // stack, and a browser adds one entry for /books/a%20b as for /books/ab.
    testWidgets(
      'router.back() leaves a page opened by a link with an escape',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
            ),
            NamedRouteDef(
              name: 'BookRoute',
              path: '/books/:id',
              builder: (context, data) => Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      Text('Book ${data.params.getString('id')}'),
                      TextButton(
                        onPressed: context.router.back,
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());

        const codec = JSONMethodCodec();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.navigation.name,
          codec.encodeMethodCall(
            const MethodCall('pushRouteInformation', {
              'location': '/books/a%20b',
              'state': null,
            }),
          ),
          null,
        );
        await tester.pumpAndSettle();
        expect(find.text('Book a b'), findsOneWidget);
        expect(router.canNavigateBack, isTrue);

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(find.text('HomeRoute'), findsOneWidget);
        expect(router.stack.map((page) => page.name), ['HomeRoute']);
      },
      // On the web the browser opens links and keeps the history.
      skip: kIsWeb,
    );
  });
}
