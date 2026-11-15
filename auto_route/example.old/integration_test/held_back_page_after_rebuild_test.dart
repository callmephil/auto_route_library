import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page that a reevaluation holds back until its guard answers goes back on
// when the guard lets it stay, also when the app rebuilt its pages meanwhile:
// a page that is given to Flutter's Navigator again gets a route again.
// Headless test: auto_route/test/reevaluatable_router/held_back_page_after_rebuild_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('held back page after rebuild', () {
    // Steps: signed in on Account, whose guard lets a signed-in user through
    // and otherwise returns without an answer and answers later. The session
    // ends, so Account is held back. The app rebuilds its pages. The user
    // signs in again, and the guard lets Account stay.
    // Was: Home stayed on screen, and Account was gone for good.
    // Should: Account is back on screen, over Home.
    testWidgets('A page held back for a guard that answers later is back '
        'after a rebuild', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final asking = <NavigationResolver>[];
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) return resolver.next();
              asking.add(resolver);
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      router.notifyAll();
      await tester.pumpAndSettle();
      expectTopPage(router, 'HomeRoute');
      asking.singleOrNull?.next();
      await tester.pumpAndSettle();

      expectTopPage(router, 'AccountRoute');
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
      ]);
      await expectBrowserUrl('/account');
    });
  });
}
