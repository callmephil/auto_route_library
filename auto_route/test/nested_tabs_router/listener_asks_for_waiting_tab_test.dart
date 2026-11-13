import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A listener of the tabs router that asks for the tab whose guard decides,
// while it is told of that change, gets the change instead of an error.
// Setup: tabs [TabA, TabB]; TabB's guard takes its time. The app listens to
// the tabs router and calls setActiveIndex with the tab it is told of, as a
// listener that syncs another tab bar does.
// Steps: on TabA, setActiveIndex(1). The guard then lets TabB in.
// Was: "Null check operator used on a null value": the router told its
// listeners before it stored the waiting change, which the listener's
// setActiveIndex(1) reads.
// Should: the listener's call waits on the same change, and TabB shows.
// Native behavior this holds to: Flutter's TabController sets its index
// before it notifies its listeners (TabController._changeIndex), so a
// listener reads, and acts on, the state it is told of.
void main() {
  testWidgets('a listener that asks for the waiting tab gets its change', (
    tester,
  ) async {
    final decision = Completer<bool>();
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const AutoTabsRouter(
            routes: [NamedRoute('TabA'), NamedRoute('TabB')],
          ),
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
                  if (await decision.future) resolver.next();
                }),
              ],
              builder: (_, _) => const Center(child: Text('TabB')),
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

    tabs
      ..addListener(askAgain)
      ..setActiveIndex(1);
    addTearDown(() => tabs.removeListener(askAgain));
    await tester.pump();
    expect(find.text('TabA'), findsOneWidget);

    decision.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tabs.activeIndex, 1);
    expect(find.text('TabB'), findsOneWidget);
  });
}
