import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page above a page whose guard let go of it (Phil's decision 4), whose
// own guard lets go when asked after the first guard's yes, comes back on
// its own guard's yes.
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

  group('let-go page above', () {
    // Steps: open Home, Account, Settings. Settings' guard lets a premium
    // user through and otherwise returns. The user signs out, no longer
    // premium; signs in again, still not premium; then is premium again.
    // Was: Settings never came back.
    // Should: Settings shows again over Account.
    testWidgets("The page above comes back on its own guard's yes", (
      tester,
    ) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final isPremium = ValueNotifier(true);
      addTearDown(isPremium.dispose);
      final session = Listenable.merge([isSignedIn, isPremium]);
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) resolver.next();
            }),
          ),
          _page(
            'SettingsRoute',
            '/settings',
            AutoRouteGuard.simple((resolver, _) {
              if (isPremium.value) resolver.next();
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      for (final name in ['AccountRoute', 'SettingsRoute']) {
        unawaited(router.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }
      isSignedIn.value = false;
      isPremium.value = false;
      await tester.pumpAndSettle();
      isSignedIn.value = true;
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');

      isPremium.value = true;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'SettingsRoute');
      expect(_names(router), ['HomeRoute', 'AccountRoute', 'SettingsRoute']);
      await expectBrowserUrl('/settings');
    });
  });
}
