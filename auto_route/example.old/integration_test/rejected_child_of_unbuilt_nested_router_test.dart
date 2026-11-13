import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A path or a link to a guarded page inside a nested router that is not
// built yet shows that router's first page when the guard rejects the page,
// at the url of the page on screen, as a canceled navigation on the web
// leaves the url of the document on screen.
// Headless test:
// auto_route/test/guards/rejected_child_of_unbuilt_nested_router_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('rejected child of unbuilt nested router', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Mail holds a nested router with its inbox and its messages. The guard
    // of a message rejects message 13.
    RootStackRouter buildRouter() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (context, _) => page('HomeRoute', [
            TextButton(
              onPressed: () =>
                  unawaited(context.router.navigatePath('/mail/13')),
              child: const Text('Open message 13'),
            ),
          ]),
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
                  (resolver, _) => resolver.route.params.getString('id') == '13'
                      ? resolver.reject()
                      : resolver.next(),
                ),
              ],
              builder: (_, data) => page('Mail ${data.params.getString('id')}'),
            ),
          ],
        ),
      ],
    );

    // Steps: open Home and tap 'Open message 13', which calls navigatePath
    // with the path of message 13, whose guard rejects it. Mail is not open.
    // Go back.
    // Was: Mail opened with nothing in it, and the url named message 13.
    // Should: Mail shows its inbox, at /mail, and back shows Home.
    testWidgets('A path to a rejected page in a shell shows its first page', (
      tester,
    ) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Open message 13'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('InboxRoute'), findsOneWidget);
      expect(find.text('Mail 13'), findsNothing);
      expect(router.currentUrl, '/mail');
      await expectBrowserUrl('/mail');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
    });

    // Steps: the app is opened at the link to message 13.
    // Was: Mail showed nothing, under the link's url.
    // Should: Mail shows its inbox, at /mail.
    testWidgets('An app opened at a rejected page shows the first page', (
      tester,
    ) async {
      final router = buildRouter();
      addTearDown(router.dispose);
      await pumpAppAtDeepLink(
        tester,
        '/mail/13',
        MaterialApp.router(
          routeInformationParser: router.defaultRouteParser(),
          routerDelegate: router.delegate(),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('InboxRoute'), findsOneWidget);
      expect(router.currentUrl, '/mail');
      await expectBrowserUrl('/mail');
    });
  });
}
