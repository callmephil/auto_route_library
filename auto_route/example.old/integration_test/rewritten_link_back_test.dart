import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, a link whose path the router writes differently, such as one
// a RedirectRoute sends on, opens its page with a history entry of its own,
// so router.back() returns to the page before.
// Headless test: auto_route/test/rewritten_link_history_entry_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('rewritten link back', () {
    // Steps: open Home, then the platform hands the running app the link
    // /b/1, which RedirectRoute sends on to /books/1. Tap 'Back', which calls
    // router.back().
    // Was: the link took Home's history entry, so 'Back' did nothing.
    // Should: Home shows again, as it does after the link /books/1.
    // Native behavior: Android puts the page a deep link opens over the back
    // stack, whatever was rewritten in its url.
    // Off the web only: on the web the browser opens links and keeps the
    // history.
    testWidgets(
      'router.back() leaves a page opened by a redirected link',
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
            RedirectRoute(path: '/b/:id', redirectTo: '/books/:id'),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());

        const codec = JSONMethodCodec();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.navigation.name,
          codec.encodeMethodCall(
            const MethodCall('pushRouteInformation', {
              'location': '/b/1',
              'state': null,
            }),
          ),
          null,
        );
        await tester.pumpAndSettle();
        final opened = (
          find.text('Book 1').evaluate().length,
          router.canNavigateBack,
        );

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(
          (
            opened,
            find.text('HomeRoute').evaluate().length,
            router.stack.length,
          ),
          ((1, true), 1, 1),
        );
      },
      skip: kIsWeb,
    );
  });
}
