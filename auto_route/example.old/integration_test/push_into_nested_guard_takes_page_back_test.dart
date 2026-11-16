import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// push of a page that was not open, with a page named for its nested router
// whose guard says no, takes the page back: the stack and the url are as
// before, and push's caller gets null.
// Native behavior this holds to: Android's conditional navigation pops
// back to the start destination when the check fails; on the web a
// canceled navigation leaves the document and its url on screen.
// Headless test:
// auto_route/test/guards/push_into_nested_guard_takes_page_back_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('push into nested guard takes page back', () {
    Widget page(String name) => Scaffold(
      body: SafeArea(child: Center(child: Text(name))),
    );

    // Steps: Home, then A pushed over it. The app pushes Mail with message
    // 13, whose guard says no.
    // Was: Mail on its inbox over A, and push's caller waiting.
    // Should: Home and A, at the url of A; push's caller gets null.
    testWidgets('A push whose nested guard says no keeps the stack', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'ARoute',
            path: '/a',
            builder: (_, _) => page('ARoute'),
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
                  AutoRouteGuard.simple((resolver, _) => resolver.reject()),
                ],
                builder: (_, _) => page('MessageRoute'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('ARoute')));
      await tester.pumpAndSettle();

      Object? got = #waiting;
      router
          .push<Object?>(
            const NamedRoute(
              'MailRoute',
              children: [
                NamedRoute('MessageRoute', params: {'id': '13'}),
              ],
            ),
          )
          .then((result) => got = result)
          .ignore();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ARoute']);
      expect(find.text('ARoute'), findsOneWidget);
      expect(find.text('InboxRoute'), findsNothing);
      expect(router.currentUrl, '/a');
      await expectBrowserUrl('/a');
      expect(got, isNull);
    });
  });
}
