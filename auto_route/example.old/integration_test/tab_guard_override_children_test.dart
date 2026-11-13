import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard on a tab route can set the tab's children with overrideNext.
// Headless test: auto_route/test/guards/tab_guard_override_children_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('tab guard override children', () {
    // Steps: tabs FeedRoute and ProfileRoute; ProfileRoute has the children
    // ProfileHomeRoute and ProfileEditRoute, and a guard that calls
    // overrideNext(children: [ProfileEditRoute]). Tap 'Open profile'.
    // Was: overrideNext threw "ProfileRoute does not have children".
    // Should: the profile tab opens on ProfileEditRoute, as a guard on a stack
    // route's overrideNext does.
    testWidgets(
      'A tab guard can set the children of its tab with overrideNext',
      (tester) async {
        Object? guardError;
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'AppRoute',
              path: '/',
              builder: (_, _) => const AutoTabsRouter(
                routes: [NamedRoute('FeedRoute'), NamedRoute('ProfileRoute')],
              ),
              children: [
                NamedRouteDef(
                  name: 'FeedRoute',
                  path: 'feed',
                  builder: (context, _) => Scaffold(
                    body: SafeArea(
                      child: TextButton(
                        onPressed: () => context.tabsRouter.setActiveIndex(1),
                        child: const Text('Open profile'),
                      ),
                    ),
                  ),
                ),
                NamedRouteDef.shell(
                  name: 'ProfileRoute',
                  path: 'profile',
                  guards: [
                    AutoRouteGuard.simple((resolver, _) {
                      try {
                        resolver.overrideNext(
                          children: [const NamedRoute('ProfileEditRoute')],
                        );
                      } on Object catch (error) {
                        guardError = error;
                        resolver.next();
                      }
                    }),
                  ],
                  children: [
                    for (final (name, path) in [
                      ('ProfileHomeRoute', ''),
                      ('ProfileEditRoute', 'edit'),
                    ])
                      NamedRouteDef(
                        name: name,
                        path: path,
                        builder: (_, _) =>
                            Scaffold(body: SafeArea(child: Text(name))),
                      ),
                  ],
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router);

        await tester.tap(find.text('Open profile'));
        await tester.pumpAndSettle();

        expect(guardError, isNull);
        expect(find.text('ProfileEditRoute'), findsOneWidget);
        expect(router.urlState.url, '/profile/edit');
      },
    );
  });
}
