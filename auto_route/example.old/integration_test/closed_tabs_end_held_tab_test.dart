import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A held tab leaves with its tabs page: no later change asks its guard, and
// its later yes opens nothing, as Flutter's Navigator disposes a route that
// leaves the stack. Headless test:
// auto_route/test/reevaluatable_router/closed_tabs_end_held_tab_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('closed tabs end held tab', () {
    // Steps: the app opens Tabs and the user selects Profile. The user signs
    // out, so Profile's guard returns without an answer and Feed shows. The
    // user closes Tabs. The session changes three times.
    // Was: each change called Profile's guard again.
    // Should: no change calls it; Home shows alone.
    testWidgets('No change asks the guard of a tab whose tabs page closed', (
      tester,
    ) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      var asks = 0;
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'TabsRoute',
            path: '/tabs',
            builder: (_, _) => const Scaffold(
              body: SafeArea(
                child: AutoTabsRouter(
                  routes: [NamedRoute('FeedRoute'), NamedRoute('ProfileRoute')],
                ),
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'FeedRoute',
                path: 'feed',
                builder: (_, _) => const Text('FeedRoute'),
              ),
              NamedRouteDef(
                name: 'ProfileRoute',
                path: 'profile',
                guards: [
                  AutoRouteGuard.simple((resolver, _) {
                    asks++;
                    if (isSignedIn.value) resolver.next();
                  }),
                ],
                builder: (_, _) => const Text('ProfileRoute'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('TabsRoute')));
      await tester.pumpAndSettle();
      router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
      await tester.pumpAndSettle();

      isSignedIn.value = false;
      session.value++;
      await tester.pumpAndSettle();
      expect(find.text('FeedRoute'), findsOneWidget);
      await router.maybePop();
      await tester.pumpAndSettle();
      asks = 0;
      for (var times = 0; times < 3; times++) {
        session.value++;
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
      expect(asks, 0);
      expectTopPage(router, 'HomeRoute');
      expect(router.stack, hasLength(1));
      await expectBrowserUrl('/');
    });
  });
}
