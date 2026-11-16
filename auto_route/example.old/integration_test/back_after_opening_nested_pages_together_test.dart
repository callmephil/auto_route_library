import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, router.back() closes one page per call after the app opens a
// page with its nested router's pages in one call.
// Headless test: auto_route/test/back_after_opening_nested_pages_together_test.dart.
//
// Native behavior this holds to: Navigator.pop takes the top-most route
// only (navigator.dart 5617 and 5652, Flutter 3.47.9), one per call. Off the
// web only: on the web, back() is the browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('nested pages opened together, off the web', () {
    // Steps: on Home, push Shell with X, Y and Z in one call. Call back()
    // three times.
    // Was: the first back() closed X, Y, Z and the shell, and showed Home.
    // Should: back() shows Y, then X, then Home.
    testWidgets(
      'back() after a push of a shell with its pages closes them one by one',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
            ),
            NamedRouteDef(
              name: 'ShellRoute',
              path: '/shell',
              builder: (_, _) => const AutoRouter(),
              children: [
                for (final (name, path) in [
                  ('XRoute', ''),
                  ('YRoute', 'y'),
                  ('ZRoute', 'z'),
                ])
                  NamedRouteDef(
                    name: name,
                    path: path,
                    builder: (_, _) => Scaffold(body: Text(name)),
                  ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(
          router.push(
            const NamedRoute(
              'ShellRoute',
              children: [
                NamedRoute('XRoute'),
                NamedRoute('YRoute'),
                NamedRoute('ZRoute'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final shown = <String>[];
        for (var i = 0; i < 3; i++) {
          router.back();
          await tester.pumpAndSettle();
          shown.add(router.currentUrl);
        }
        expect(shown, ['/shell/y', '/shell', '/']);
        expect(find.text('HomeRoute'), findsOneWidget);
      },
      skip: kIsWeb,
    );
  });
}
