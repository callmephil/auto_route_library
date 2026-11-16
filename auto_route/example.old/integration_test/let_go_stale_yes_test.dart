import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard that let go of its page (Phil's decision 4) and is asked again by
// a sign-in answers yes from before a later sign-out: the page stays off,
// as Flutter's Router drops an older transaction's answer once newer route
// information has arrived.
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

  group('let-go stale yes', () {
    // Steps: on Account, the user signs out, so its guard lets go. Signed
    // in again, the guard reads the session and awaits a request; the user
    // signs out while it awaits; then the request completes.
    // Was: Account came back for the signed-out user.
    // Should: Home stays on screen, at /.
    testWidgets('A yes from before the last sign-out leaves the page off', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final requests = <Completer<void>>[];
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) async {
              final wasSignedIn = session.value;
              if (requests.lastOrNull case final waiting?) {
                await waiting.future;
              }
              if (wasSignedIn) resolver.next();
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      session.value = false;
      await tester.pumpAndSettle();

      final request = Completer<void>();
      requests.add(request);
      session.value = true;
      await tester.pump();
      session.value = false;
      await tester.pump();
      request.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(_names(router), ['HomeRoute']);
      await expectBrowserUrl('/');
    });
  });
}
