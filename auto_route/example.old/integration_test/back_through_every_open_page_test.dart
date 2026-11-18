import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/pages.dart';

// Issue callmephil/auto_route_library#17: the app's own history kept at most
// 21 entries, so after 30 pushes back() took 20 steps and then did
// nothing, with 11 pages still open.
// Native behavior: Flutter's Navigator keeps every route until it is popped.
// Android's back stack and iOS's UINavigationController have no fixed
// length, and back closes each page down to the first one.
// Headless test: auto_route/test/back_through_every_open_page_test.dart.
//
// Off the web only: on the web, back() walks the browser's history.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back through every open page', () {
    // Steps: push PageRoute 30 times, then call back() until canNavigateBack
    // is false.
    // Should: 30 steps, one page each, down to Home alone.
    Future<void> closesAllPages(WidgetTester tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const TextPage('Home'),
          ),
          NamedRouteDef(
            name: 'PageRoute',
            path: '/p/:n',
            builder: (_, data) =>
                TextPage('Page ${data.params.getString('n')}'),
          ),
        ],
      );
      await pumpRouterAppWithConfig(tester, router);
      for (var n = 1; n <= 30; n++) {
        unawaited(
          router.push(PageRouteInfo('PageRoute', rawPathParams: {'n': n})),
        );
        await tester.pumpAndSettle();
      }
      expect(router.stack.length, 31);
      var steps = 0;
      while (router.canNavigateBack && steps < 100) {
        final before = router.stack.length;
        router.back();
        await tester.pumpAndSettle();
        expect(router.stack.length, before - 1);
        steps++;
      }
      expect(steps, 30);
      expect(find.text('Home'), findsOneWidget);
      expect(router.canNavigateBack, isFalse);
    }

    testWidgets('back() closes all 30 pages', closesAllPages, skip: kIsWeb);
  });
}
