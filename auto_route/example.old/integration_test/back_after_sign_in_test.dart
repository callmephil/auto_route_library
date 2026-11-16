import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, router.back() never shows a page the app removed: after a
// sign-in that ends in replaceAll, it never shows the sign-in page again.
// Headless test: auto_route/test/back_after_removing_page_test.dart.
//
// Native behavior this holds to: a view controller left out of UIKit's
// setViewControllers(_:animated:) is gone from the navigation stack, and an
// Android activity that was finished is no longer in the back stack, so back
// never returns to it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after sign-in', () {
    // Steps: on Welcome, tap 'Sign in', then 'Done', which calls
    // replaceAll([Home]). Tap 'Settings', then tap 'Back' twice; its handler
    // is the router's back method.
    // Was: the second tap opened the sign-in page again, and the history
    // still held Welcome.
    // Should: the first tap shows Home, the second does nothing: Home is the
    // only page left, and the history holds its entry alone.
    // Off the web only: on the web, back() is the browser's own back step.
    testWidgets(
      'back() after a sign-in that ends in replaceAll never shows sign-in',
      (tester) async {
        Widget page(
          BuildContext context,
          String name,
          (String, VoidCallback)? next,
        ) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Text(name),
                if (next case (final label, final onPressed))
                  TextButton(onPressed: onPressed, child: Text(label)),
                TextButton(
                  onPressed: context.router.back,
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        );
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'WelcomeRoute',
              path: '/',
              builder: (context, _) => page(context, 'WelcomeRoute', (
                'Sign in',
                () => unawaited(
                  context.router.push(const NamedRoute('SignInRoute')),
                ),
              )),
            ),
            NamedRouteDef(
              name: 'SignInRoute',
              path: '/sign-in',
              builder: (context, _) => page(context, 'SignInRoute', (
                'Done',
                () => unawaited(
                  context.router.replaceAll(const [NamedRoute('HomeRoute')]),
                ),
              )),
            ),
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/home',
              builder: (context, _) => page(context, 'HomeRoute', (
                'Settings',
                () => unawaited(
                  context.router.push(const NamedRoute('SettingsRoute')),
                ),
              )),
            ),
            NamedRouteDef(
              name: 'SettingsRoute',
              path: '/settings',
              builder: (context, _) => page(context, 'SettingsRoute', null),
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        for (final label in ['Sign in', 'Done', 'Settings', 'Back', 'Back']) {
          await tester.tap(find.text(label).hitTestable());
          await tester.pumpAndSettle();
        }

        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        expect(find.text('SignInRoute'), findsNothing);
        expect(router.navigationHistory.length, 1);
      },
      skip: kIsWeb,
    );
  });
}
