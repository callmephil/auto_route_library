import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// When the guards are reevaluated, as after a sign-out, the guards of the
// active tab are asked again, and a tab they keep out leaves the screen.
// Headless test:
// auto_route/test/reevaluatable_router/reevaluate_asks_active_tab_guards_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('reevaluate asks active tab guards', () {
    for (final kind in _Tabs.values) {
      // Steps: tabs [FeedTab, ProfileTab]; ProfileTab's guard lets in a
      // signed-in user only, and the sign-in state is the router's
      // reevaluateListenable. Signed in, tap 'Open profile', then 'Sign out'.
      // Was: ProfileTab stayed on screen.
      // Should: FeedTab shows, as the README promises the listenable keeps
      // private pages for signed-in users only.
      testWidgets('${kind.name}: signing out on a guarded tab leaves it', (
        tester,
      ) async {
        final isSignedIn = ValueNotifier(true);
        addTearDown(isSignedIn.dispose);
        const routes = [
          NamedRoute<Object?>('FeedTab'),
          NamedRoute<Object?>('ProfileTab'),
        ];
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => Scaffold(
                body: switch (kind) {
                  .indexedStack => const AutoTabsRouter(routes: routes),
                  .pageView => const AutoTabsRouter.pageView(routes: routes),
                  .tabBar => const AutoTabsRouter.tabBar(routes: routes),
                },
              ),
              children: [
                NamedRouteDef(
                  name: 'FeedTab',
                  path: 'feed',
                  builder: (context, _) => SafeArea(
                    child: Column(
                      children: [
                        const Text('FeedTab'),
                        TextButton(
                          onPressed: () => context.tabsRouter.setActiveIndex(1),
                          child: const Text('Open profile'),
                        ),
                      ],
                    ),
                  ),
                ),
                NamedRouteDef(
                  name: 'ProfileTab',
                  path: 'profile',
                  guards: [
                    AutoRouteGuard.simple((resolver, _) {
                      if (isSignedIn.value) {
                        resolver.next();
                      } else {
                        resolver.reject();
                      }
                    }),
                  ],
                  builder: (_, _) => SafeArea(
                    child: Column(
                      children: [
                        const Text('ProfileTab'),
                        TextButton(
                          onPressed: () => isSignedIn.value = false,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(
          tester,
          router,
          reevaluationNotifier: isSignedIn,
        );

        await tester.tap(find.text('Open profile').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('ProfileTab').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Sign out').hitTestable());
        await tester.pumpAndSettle();

        expect(find.text('ProfileTab').hitTestable(), findsNothing);
        expect(find.text('FeedTab').hitTestable(), findsOneWidget);
        expect(router.urlState.url, '/feed');
      });
    }
  });
}

enum _Tabs { indexedStack, pageView, tabBar }
