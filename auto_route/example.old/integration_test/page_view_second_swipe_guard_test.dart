import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// In AutoTabsRouter.pageView the active tab stays on screen while the guard
// of the tab swiped to decides, as the README promises and as a tab
// UITabBarController refuses stays unselected.
// Headless test: auto_route/test/nested_tabs_router/page_view_second_swipe_guard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('page view second swipe guard', () {
    // Steps: the tabs TabA and TabB, and TabB's guard waits. Swipe to TabB
    // twice, then let the guard accept.
    // Was: after the second swipe the view rested on TabB's empty page.
    // Should: TabA shows until the guard accepts, then TabB.
    testWidgets('A second swipe to a deciding tab keeps the active tab', (
      tester,
    ) async {
      final decision = Completer<bool>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: AutoTabsRouter.pageView(routes: _kTabs)),
            children: [
              NamedRouteDef(
                name: 'TabA',
                path: 'a',
                builder: (_, _) => const Center(child: Text('TabA')),
              ),
              NamedRouteDef(
                name: 'TabB',
                path: 'b',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    if (await decision.future) {
                      resolver.next();
                    } else {
                      resolver.reject();
                    }
                  }),
                ],
                builder: (_, _) => const Center(child: Text('TabB')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

      for (var swipe = 0; swipe < 2; swipe++) {
        await swipeToNextPage(tester, find.text('TabA'));
        await tester.pumpAndSettle();
        expect(tabs.activeIndex, 0);
        expect(find.text('TabA').hitTestable(), findsOneWidget);
        expect(find.text('TabB'), findsNothing);
      }

      decision.complete(true);
      await tester.pumpAndSettle();
      expect(tabs.activeIndex, 1);
      expect(find.text('TabB').hitTestable(), findsOneWidget);
    });
  });
}

const _kTabs = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('TabB')];
