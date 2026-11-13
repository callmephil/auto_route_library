import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A listener of the tabs router that asks for the tab whose guard decides,
// while it is told of that change, gets the change instead of an error.
// Headless test:
// auto_route/test/nested_tabs_router/listener_asks_for_waiting_tab_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('listener asks for waiting tab', () {
    // Steps: tabs [TabA, TabB]; TabB's guard takes its time. The app listens
    // to the tabs router and calls setActiveIndex(1) when told. Tap 'Open
    // tab B'; the guard then lets TabB in.
    // Was: "Null check operator used on a null value" in the listener.
    // Should: TabB shows, as Flutter's TabController sets its index before
    // it tells its listeners.
    testWidgets('a listener that asks for the waiting tab gets its change', (
      tester,
    ) async {
      final decision = Completer<bool>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter(
                routes: [NamedRoute('TabA'), NamedRoute('TabB')],
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'TabA',
                path: 'a',
                builder: (context, _) => SafeArea(
                  child: TextButton(
                    onPressed: () => context.tabsRouter.setActiveIndex(1),
                    child: const Text('Open tab B'),
                  ),
                ),
              ),
              NamedRouteDef(
                name: 'TabB',
                path: 'b',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    if (await decision.future) resolver.next();
                  }),
                ],
                builder: (_, _) => const SafeArea(child: Text('TabB')),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
      var asks = 0;
      void askAgain() {
        asks++;
        if (asks == 1) tabs.setActiveIndex(1);
      }

      tabs.addListener(askAgain);
      addTearDown(() => tabs.removeListener(askAgain));

      await tester.tap(find.text('Open tab B'));
      await tester.pumpAndSettle();
      decision.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('TabB'), findsOneWidget);
      expect(router.urlState.url, '/b');
    });
  });
}
