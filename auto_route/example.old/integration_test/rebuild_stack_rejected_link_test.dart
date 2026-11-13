import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// With rebuildStackOnDeepLink, a link a guard rejects keeps the stack, as a
// refused navigation changes nothing; a link the guards let in replaces it.
// Headless test: auto_route/test/guards/rebuild_stack_rejected_link_test.dart
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

  group('rebuild stack rejected link', () {
    // Steps: with rebuildStackOnDeepLink, open Home and push Details, then
    // the platform hands the running app the link /secret, whose guard
    // rejects it; then the link /other, which the app lets in.
    // Was: the rejected link closed Details and every page above Home.
    // Should: Details stays on screen after /secret; /other then replaces
    // the stack.
    testWidgets(
      'A rejected link keeps the stack when rebuildStackOnDeepLink is on',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('DetailsRoute', '/details'),
              ('OtherRoute', '/other'),
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
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            includePrefixMatches: true,
          ),
        );
        unawaited(router.push(const NamedRoute('DetailsRoute')));
        await tester.pumpAndSettle();

        await openLink(tester, '/secret');

        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'DetailsRoute',
        ]);
        expect(find.text('DetailsRoute'), findsOneWidget);
        expect(find.text('SecretRoute'), findsNothing);

        await openLink(tester, '/other');

        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'OtherRoute',
        ]);
        expect(find.text('OtherRoute'), findsOneWidget);
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );

    // Steps: with rebuildStackOnDeepLink, open Home and push Details. The
    // platform hands the app the link /account, whose guard shows a sign-in
    // page in the place of the open pages; then the link /secret, which its
    // guard rejects. The user cancels the sign-in, so the first guard
    // rejects too.
    // Was: no page was left, and the screen was blank.
    // Should: Home and Details are back, as after the same rejection with no
    // second link.
    testWidgets(
      'The pages come back when a second, rejected link came in while the '
      'sign-in page of a link was open',
      (tester) async {
        final signingIn = <NavigationResolver>[];
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('DetailsRoute', '/details'),
              ('SignInRoute', '/sign-in'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => page(name),
              ),
            NamedRouteDef(
              name: 'AccountRoute',
              path: '/account',
              guards: [
                AutoRouteGuard.simple((resolver, _) {
                  signingIn.add(resolver);
                  unawaited(
                    resolver.redirectUntil(const NamedRoute('SignInRoute')),
                  );
                }),
              ],
              builder: (_, _) => page('AccountRoute'),
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
        await pumpRouterConfigApp(
          tester,
          router.config(rebuildStackOnDeepLink: true),
        );
        unawaited(router.push(const NamedRoute('DetailsRoute')));
        await tester.pumpAndSettle();

        await openLink(tester, '/account');
        final atSignIn = router.stack.map((page) => page.name).toList();
        await openLink(tester, '/secret');
        signingIn.firstOrNull?.reject();
        await tester.pumpAndSettle();

        expect(atSignIn, ['SignInRoute']);
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'DetailsRoute',
        ]);
        expect(find.text('DetailsRoute'), findsOneWidget);
      },
      skip: kIsWeb,
    );
  });
}
