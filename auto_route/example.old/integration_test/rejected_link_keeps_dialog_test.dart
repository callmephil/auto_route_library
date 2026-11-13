import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link the app turns down keeps the dialog the user has open, also when a
// guard in a nested router turns it down; a link the app lets in closes it,
// as a refused navigation changes nothing.
// Headless test: auto_route/test/guards/rejected_link_keeps_dialog_test.dart
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

  group('rejected link keeps dialog', () {
    // Steps: open Home and a dialog on it, then the platform hands the
    // running app the link /secret, whose guard rejects it; then the link
    // /other, which the app lets in.
    // Was: the rejected link closed the dialog, and what was typed in it.
    // Should: the dialog stays over Home after /secret, and closes as Other
    // opens.
    testWidgets(
      'A link a guard rejects keeps the open dialog',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => page('HomeRoute'),
            ),
            NamedRouteDef(
              name: 'OtherRoute',
              path: '/other',
              builder: (_, _) => page('OtherRoute'),
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
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await openLink(tester, '/secret');

        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(find.text('SecretRoute'), findsNothing);

        await openLink(tester, '/other');

        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'OtherRoute',
        ]);
        expect(find.text('Unsaved draft'), findsNothing);
        expect(find.text('OtherRoute'), findsOneWidget);
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );

    // Steps: the mail page holds a nested router and shows mail 42 under
    // a dialog. Then the platform hands the running app a link to mail 13,
    // which the guard in the nested router rejects, and then a link to
    // mail 7, which the app lets in.
    // Was: the rejected link closed the dialog.
    // Should: the dialog stays over mail 42 after /mail/13, and closes as
    // mail 7 opens.
    testWidgets(
      'A link a nested guard rejects keeps the open dialog',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => page('HomeRoute'),
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
                    AutoRouteGuard.simple(
                      (resolver, _) =>
                          resolver.route.params.getString('id') == '13'
                          ? resolver.reject()
                          : resolver.next(),
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
        await openLink(tester, '/mail/42');
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();

        await openLink(tester, '/mail/13');

        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(find.text('Mail 42'), findsOneWidget);
        expect(router.currentUrl, '/mail/42');

        await openLink(tester, '/mail/7');

        expect(find.text('Unsaved draft'), findsNothing);
        expect(find.text('Mail 7'), findsOneWidget);
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );
  });
}
