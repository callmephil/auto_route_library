import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, router.back() still leaves a link into a nested router whose
// guard waits, and after the guard's yes it walks from the page let in to
// Home.
// Headless test: auto_route/test/back_while_nested_guard_waits_test.dart.
//
// Native behavior this holds to: Navigator.pop takes the top-most route
// only (navigator.dart 5617 and 5652, Flutter 3.47.9), and every page it
// must reach has a way back. Off the web only: on the web, back() is the
// browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('a link into a nested router whose guard waits, off the web', () {
    // Steps: on Home, the platform hands the app the link /shell/gx, whose
    // guard waits. The router notifies meanwhile; then the guard says yes.
    // Call back().
    // Was: the link's entry was lost, so back() did nothing on GX.
    // Should: back() shows Home.
    testWidgets(
      'back() after the guard lets the link in shows Home',
      (tester) async {
        final answer = Completer<bool>();
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
                NamedRouteDef(
                  name: 'XRoute',
                  path: '',
                  builder: (_, _) => const Scaffold(body: Text('XRoute')),
                ),
                NamedRouteDef(
                  name: 'GXRoute',
                  path: 'gx',
                  guards: [
                    AutoRouteGuard.simple((resolver, _) async {
                      final isLetIn = await answer.future;
                      isLetIn ? resolver.next() : resolver.reject();
                    }),
                  ],
                  builder: (_, _) => const Scaffold(body: Text('GXRoute')),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(tester.binding.handlePushRoute('/shell/gx'));
        await tester.pumpAndSettle();
        // Stands for any change elsewhere in the app's routers meanwhile.
        router.notifyListeners();
        answer.complete(true);
        await tester.pumpAndSettle();
        final onLink = router.currentUrl;

        router.back();
        await tester.pumpAndSettle();

        expect((onLink, router.currentUrl), ('/shell/gx', '/'));
        expect(find.text('HomeRoute'), findsOneWidget);
      },
      skip: kIsWeb,
    );
  });
}
