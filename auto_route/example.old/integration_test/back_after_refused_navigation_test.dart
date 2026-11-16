import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, router.back() never opens a page whose guard turned the
// app's own navigation down.
// Headless test: auto_route/test/back_after_refused_navigation_test.dart.
//
// Native behavior this holds to: a Navigator's history is populated from
// its pages alone (Navigator.pages, navigator.dart 1610, Flutter 3.47.9), so
// a page a guard never let in has no place a pop returns to. Off the web
// only: on the web, back() is the browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a navigation its guard turned down, off the web', () {
    // Steps: on Home, navigatePath('/mail/77'); while Message's guard
    // decides, push Settings; the guard says no. Call back().
    // Was: back() opened Mail on message 77.
    // Should: back() shows Home, and the history holds Home alone.
    testWidgets(
      'back() after the guard says no shows Home, never Mail',
      (tester) async {
        final answer = Completer<bool>();
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('SettingsRoute', '/settings'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => Scaffold(body: Text(name)),
              ),
            NamedRouteDef(
              name: 'MailRoute',
              path: '/mail',
              builder: (_, _) => const Scaffold(body: AutoRouter()),
              children: [
                NamedRouteDef(
                  name: 'InboxRoute',
                  path: '',
                  builder: (_, _) => const Text('InboxRoute'),
                ),
                NamedRouteDef(
                  name: 'MessageRoute',
                  path: ':id',
                  guards: [
                    AutoRouteGuard.simple((resolver, _) async {
                      final isLetIn = await answer.future;
                      isLetIn ? resolver.next() : resolver.reject();
                    }),
                  ],
                  builder: (_, _) => const Text('MessageRoute'),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.navigatePath('/mail/77', includePrefixMatches: true));
        await tester.pumpAndSettle();
        unawaited(router.push(const NamedRoute('SettingsRoute')));
        await tester.pumpAndSettle();
        answer.complete(false);
        await tester.pumpAndSettle();

        router.back();
        await tester.pumpAndSettle();

        expect(router.currentUrl, '/');
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(router.navigationHistory.length, 1);
      },
      skip: kIsWeb,
    );
  });
}
