import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Every page that a guard's rejection on reevaluateGuards() closes hears
// RouteLeaveKind.removed, the pages above the rejected page too: no pop
// took them off, and a pop on Android, iOS and the web is a back action or
// a pop call. Headless test:
// auto_route/test/reevaluatable_router/pages_above_rejected_page_removed_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pages above rejected page removed', () {
    // Steps: the app opens Account, then Settings. The user signs out, and
    // Account's guard rejects.
    // Was: Account heard removed, Settings heard popped.
    // Should: both hear removed, and Home shows.
    testWidgets('Account and Settings hear removed', (tester) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final heard = <String>[];
      NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) =>
          .new(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => AutoRouteLeaveListener(
              onLeave: (kind) => heard.add('$name ${kind.name}'),
              child: Scaffold(body: SafeArea(child: Text(name))),
            ),
          );
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          page(
            'AccountRoute',
            '/account',
            guard: AutoRouteGuard.simple(
              (resolver, _) =>
                  session.value ? resolver.next() : resolver.reject(),
            ),
          ),
          page('SettingsRoute', '/settings'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();
      heard.clear();

      session.value = false;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectTopPage(router, 'HomeRoute');
      expect(router.stack, hasLength(1));
      expect(
        heard,
        unorderedEquals(['AccountRoute removed', 'SettingsRoute removed']),
      );
      await expectBrowserUrl('/');
    });
  });
}
