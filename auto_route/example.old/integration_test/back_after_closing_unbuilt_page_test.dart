import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// router.back() opens no page the app closed before it was ever built, as
// a screen that was closed is in no back stack.
// Headless test: auto_route/test/back_after_closing_unbuilt_page_test.dart
//
// Off the web only: the test is about the app's own history. On the web
// back() is the browser's history.back().
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after closing unbuilt page', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home, the list and an item. Tap 'Open and close the
    // preview'. Its handler pushes the preview and pops it, with no await
    // between the calls. Then tap 'Step back', which calls back().
    // Was: the preview, a page the app had closed, came on screen.
    // Should: the list is on screen, and one more step back shows Home.
    testWidgets(
      'A step back after a page was pushed and popped at once shows the '
      'page before',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('ListRoute', '/list'),
              ('PreviewRoute', '/preview'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => page(name),
              ),
            NamedRouteDef(
              name: 'ItemRoute',
              path: '/item',
              builder: (context, _) => page('ItemRoute', [
                TextButton(
                  onPressed: () {
                    unawaited(
                      context.router.push(const NamedRoute('PreviewRoute')),
                    );
                    context.router.pop();
                  },
                  child: const Text('Open and close the preview'),
                ),
                TextButton(
                  onPressed: context.router.back,
                  child: const Text('Step back'),
                ),
              ]),
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        for (final name in ['ListRoute', 'ItemRoute']) {
          unawaited(router.push(NamedRoute(name)));
          await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Open and close the preview'));
        await tester.pumpAndSettle();
        final afterClosing = router.navigationHistory.length;
        await tester.tap(find.text('Step back'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(afterClosing, 3);
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'ListRoute',
        ]);
        expect(find.text('ListRoute'), findsOneWidget);
        expect(find.text('PreviewRoute'), findsNothing);
        expect(router.navigationHistory.length, 2);
      },
      // On the web back() is the browser's history.back().
      skip: kIsWeb,
    );
  });
}
