import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// replaceAll ends the wait of a page held for its guard: the caller gets
// null at the replaceAll, and a later sign-in opens nothing, as Flutter's
// Navigator completes each route that pushAndRemoveUntil removes at the
// removal. Headless test:
// auto_route/test/reevaluatable_router/replace_all_ends_held_page_test.dart
NamedRouteDef _page(String name, String path, {AutoRouteGuard? guard}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaceAll ends held page', () {
    // Steps: the app opens Account. The user signs out, so Account's guard
    // returns without an answer and Account leaves the screen. The app
    // calls replaceAll([Other]), then the user signs in again.
    // Was: Account's caller waited until the sign-in.
    // Should: the caller gets null at the replaceAll; Other stays alone.
    testWidgets('The caller of the held page gets null at the replaceAll', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            guard: AutoRouteGuard.simple((resolver, _) {
              if (session.value) resolver.next();
            }),
          ),
          _page('OtherRoute', '/other'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      final results = <Object?>[];
      unawaited(
        router.push<String>(const NamedRoute('AccountRoute')).then(results.add),
      );
      await tester.pumpAndSettle();

      session.value = false;
      await tester.pumpAndSettle();
      unawaited(router.replaceAll([const NamedRoute('OtherRoute')]));
      await tester.pumpAndSettle();
      final resultsAtReplaceAll = List.of(results);
      session.value = true;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(resultsAtReplaceAll, [null]);
      expectTopPage(router, 'OtherRoute');
      expect(router.stack, hasLength(1));
      expect(find.text('AccountRoute'), findsNothing);
      await expectBrowserUrl('/other');
    });
  });
}
