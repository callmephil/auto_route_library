import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/restorable_app.dart';

// A nested page that inherits a path param from its parent route comes back
// after state restoration.
// Headless test: auto_route/test/restoration/restore_inherited_path_param_test.dart
//
// WidgetTester.restartAndRestore ends the app's widget tree and starts it
// again from the data Flutter saved for restoration, which is what the
// platform hands back to an app it ended. A new router is built.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('restore inherited path param', () {
    // Flutter's state restoration doesn't run on the web, so the routers save
    // their pages only off the web.
    RootStackRouter buildRouter() => .build(
      routes: [
        AutoRoute(path: '/', page: namedPage('HomeRoute'), initial: true),
        AutoRoute(
          path: '/product/:id',
          page: PageInfo('ProductRoute', builder: (_) => const AutoRouter()),
          children: [
            AutoRoute(path: '', page: namedPage('ProductOverviewRoute')),
            AutoRoute(
              path: 'review',
              page: PageInfo(
                'ProductReviewRoute',
                builder: (data) => Scaffold(
                  body: Text(
                    'Review of ${data.inheritedPathParams.getInt('id')}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    // Steps: open product 5, then its review page, restore the app, then go
    // back.
    // Was: the review page was gone; the product showed its overview.
    // Should: the review of product 5 shows again, and back shows the
    // overview, as a restored screen on Android and iOS gets the arguments
    // it was saved with.
    testWidgets('the review page of product 5 comes back', (tester) async {
      await pumpRestorableApp(tester, buildRouter);
      var router = RestorableRouterApp.router;
      unawaited(router.pushPath('/product/5'));
      await tester.pumpAndSettle();
      unawaited(router.pushPath('/product/5/review'));
      await tester.pumpAndSettle();
      final earlier = find.text('Review of 5').evaluate().length;

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      router = RestorableRouterApp.router;
      expect((earlier, find.text('Review of 5').evaluate().length), (1, 1));
      expect(router.currentPath, '/product/5/review');

      await systemBack(tester);
      expect(find.text('ProductOverviewRoute'), findsOneWidget);
    }, skip: kIsWeb);
  });
}
