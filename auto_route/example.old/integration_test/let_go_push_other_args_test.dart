import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A push of a let-go page's route with other arguments opens another page
// (Phil's decision 4): both come back on the yes, as a push opens a new
// screen on iOS (pushViewController(_:animated:)) and Android.
// Headless test: auto_route/test/reevaluatable_router/let_go_answer_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('let-go push other args', () {
    // Steps: open item 1, whose guard lets a signed-in user through and
    // otherwise returns. The user signs out; the app pushes item 2. The user
    // signs in, then goes back.
    // Was: item 1 was gone, and back from item 2 showed Home.
    // Should: back from the top item shows the other one.
    testWidgets('Both items come back, and back shows the other one', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('Home'))),
          ),
          NamedRouteDef(
            name: 'ItemRoute',
            path: '/item/:id',
            guards: [
              AutoRouteGuard.simple((resolver, _) {
                if (session.value) resolver.next();
              }),
            ],
            builder: (_, data) => Scaffold(
              body: SafeArea(child: Text('Item ${data.params.getInt('id')}')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.pushPath('/item/1'));
      await tester.pumpAndSettle();
      session.value = false;
      await tester.pumpAndSettle();
      unawaited(router.pushPath('/item/2'));
      await tester.pumpAndSettle();
      session.value = true;
      await tester.pumpAndSettle();
      final items = [
        for (final page in router.stack) page.routeData.params.optInt('id'),
      ];

      await systemBack(tester);

      expect(tester.takeException(), isNull);
      expect(items, unorderedEquals([null, 1, 2]));
      expect(router.stack, hasLength(2));
      expect(find.text('Home'), findsNothing);
    });
  });
}
