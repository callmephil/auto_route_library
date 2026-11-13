import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Of two navigate calls to a page that is open, the first waiting on its
// guard, the stack keeps one page of the route, as Flutter's Navigator
// requires every page of its list to have its own key.
// Headless test: auto_route/test/guards/two_navigations_to_one_page_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('two navigations to one page', () {
    // Steps: open Home and message 42 over it. Call navigate to message 13
    // and, while its guard waits for an answer, navigate to message 14, which
    // opens in the place of 42. Then the guard lets message 13 in. Go back.
    // Was: message 13 went on as a second page with the key of the page that
    // showed 14, and the navigator threw its duplicate key error.
    // Should: one message page, which shows message 13, and back shows Home.
    testWidgets('The later answer shows in the one page of the route', (
      tester,
    ) async {
      final answerFor13 = Completer<void>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'MessageRoute',
            path: '/message/:id',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                if (resolver.route.params.getString('id') == '13') {
                  await answerFor13.future;
                }
                resolver.next();
              }),
            ],
            builder: (_, data) => Scaffold(
              body: SafeArea(
                child: Text('Message ${data.params.getString('id')}'),
              ),
            ),
          ),
        ],
      );
      NamedRoute message(String id) => .new('MessageRoute', params: {'id': id});
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(message('42')));
      await tester.pumpAndSettle();

      unawaited(router.navigate(message('13')));
      await tester.pumpAndSettle();
      unawaited(router.navigate(message('14')));
      await tester.pumpAndSettle();
      expect(find.text('Message 14'), findsOneWidget);

      answerFor13.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'MessageRoute',
      ]);
      expect(find.text('Message 13'), findsOneWidget);
      expect(find.text('Message 14'), findsNothing);
      await expectBrowserUrl('/message/13');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
    });
  });
}
