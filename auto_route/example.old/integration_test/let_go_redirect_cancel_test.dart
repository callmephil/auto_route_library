import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard that let go of its page (Phil's decision 4), then shows a sign-in
// page from a callback with redirectUntil: when the user closes the sign-in
// page, the page stays off, as a rejection closes it for good.
// Headless test: auto_route/test/reevaluatable_router/let_go_answer_test.dart
NamedRouteDef _page(String name, String path, [AutoRouteGuard? guard]) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
);

List<String> _names(StackRouter router) =>
    router.stack.map((page) => page.routeData.name).toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('let-go redirect cancel', () {
    // Steps: on Account, the user signs out. Account's guard returns, then
    // calls redirectUntil(SignInRoute()) from a callback. The user goes
    // back from the sign-in page.
    // Was: Account showed again, at /account.
    // Should: Home shows, at /.
    testWidgets('Closing the sign-in page leaves the page off', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final later = Completer<void>();
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (session.value) return resolver.next();
              unawaited(
                later.future.then(
                  (_) =>
                      resolver.redirectUntil(const NamedRoute('SignInRoute')),
                ),
              );
            }),
          ),
          _page('SignInRoute', '/sign-in'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      session.value = false;
      await tester.pumpAndSettle();
      later.complete();
      await tester.pumpAndSettle();
      expectTopPage(router, 'SignInRoute');

      await systemBack(tester);

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(_names(router), ['HomeRoute']);
      await expectBrowserUrl('/');
    });
  });
}
