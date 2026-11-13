import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link a guard rejects leaves an earlier link that waits behind a sign-in
// page to open once the user signs in.
// Headless test: auto_route/test/guards/rejected_link_keeps_earlier_link_test.dart
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

  group('rejected link keeps earlier link', () {
    // Steps: the platform hands the app /account, whose guard shows the
    // sign-in page; then /guarded, whose guard rejects it; then the user
    // taps "Sign in".
    // Was: Account never opened; the sign-in page closed on Home.
    // Should: Account opens.
    testWidgets(
      'A rejected link leaves the link behind a sign-in page to open',
      (tester) async {
        NavigationResolver? signingIn;
        Widget page(String name) => Scaffold(
          body: SafeArea(child: Center(child: Text(name))),
        );
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => page('HomeRoute'),
            ),
            NamedRouteDef(
              name: 'LoginRoute',
              path: '/login',
              builder: (_, _) => Scaffold(
                body: SafeArea(
                  child: Center(
                    child: TextButton(
                      onPressed: () => signingIn?.next(),
                      child: const Text('Sign in'),
                    ),
                  ),
                ),
              ),
            ),
            NamedRouteDef(
              name: 'GuardedRoute',
              path: '/guarded',
              guards: [
                AutoRouteGuard.simple((resolver, _) => resolver.reject()),
              ],
              builder: (_, _) => page('GuardedRoute'),
            ),
            NamedRouteDef(
              name: 'AccountRoute',
              path: '/account',
              guards: [
                AutoRouteGuard.simple((resolver, _) {
                  signingIn = resolver;
                  unawaited(
                    resolver.redirectUntil(const NamedRoute('LoginRoute')),
                  );
                }),
              ],
              builder: (_, _) => page('AccountRoute'),
            ),
          ],
        );
        await pumpRouterConfigApp(
          tester,
          router.config(includePrefixMatches: true),
        );

        await openLink(tester, '/account');
        expect(find.text('Sign in'), findsOneWidget);
        await openLink(tester, '/guarded');
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'LoginRoute',
        ]);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();

        expect(find.text('AccountRoute'), findsOneWidget);
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'AccountRoute',
        ]);
        expect(router.currentUrl, '/account');
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );
  });
}
