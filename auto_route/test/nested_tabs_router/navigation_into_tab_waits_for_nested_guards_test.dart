import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// callmephil/auto_route_library#7: navigate and navigatePath into the
// nested router of a tab completed before the guards there answered.
// Setup: Home at '/' holds the tabs Feed and Profile. Profile holds a stack
// router with ProfileHome at '' and Orders at 'orders', whose guard waits
// for the test. Account at '/account' holds the same stack router.
// Steps: show the Profile tab, or stay on Feed. Await navigatePath
// '/profile/orders', or navigate to it. The guard waits, then says no or
// yes.
// Was: the future completed at once, while the guard still waited.
// Should: the future completes only once the guard has answered: after a
// no; after a yes, when Orders closes, as for a page the call reaches in a
// stack. The stack page Account, which already waited, is the neighbor.
// Native behavior this holds to: Flutter's Router awaits the future of the
// delegate's setNewRoutePath before it rebuilds
// (_processParsedRouteInformation, router.dart, Flutter 3.50.0): a
// navigation completes once the delegate has applied it.
final _guard = HeldGuard();

List<NamedRouteDef> _accountPages() => [
  NamedRouteDef(
    name: 'ProfileHomeRoute',
    path: '',
    builder: (_, _) => const Text('ProfileHome'),
  ),
  NamedRouteDef(
    name: 'OrdersRoute',
    path: 'orders',
    guards: [_guard],
    builder: (_, _) => const Text('Orders'),
  ),
];

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const AutoTabsRouter(
        routes: [NamedRoute('FeedTab'), NamedRoute('ProfileTab')],
      ),
      children: [
        NamedRouteDef(
          name: 'FeedTab',
          path: 'feed',
          builder: (_, _) => const Text('Feed'),
        ),
        NamedRouteDef(
          name: 'ProfileTab',
          path: 'profile',
          builder: (_, _) => const AutoRouter(),
          children: _accountPages(),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'AccountRoute',
      path: '/account',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: _accountPages(),
    ),
  ],
);

enum _Call { navigatePath, navigate }

enum _Start { profileShown, feedShown, stackPage }

void main() {
  for (final start in _Start.values) {
    for (final call in _Call.values) {
      for (final isYes in [false, true]) {
        testWidgets('${call.name} to Orders, ${start.name}, the guard says '
            '${isYes ? 'yes' : 'no'}', (tester) async {
          _guard
            ..clear()
            ..holdCall();
          final router = _router();
          await pumpRouterConfigApp(tester, router.config());
          final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
          if (start == .profileShown) {
            tabs.setActiveIndex(1);
            await tester.pumpAndSettle();
          }
          final isStack = start == .stackPage;
          var isDone = false;
          final Future<void> navigation = switch (call) {
            .navigatePath => router.navigatePath(
              isStack ? '/account/orders' : '/profile/orders',
            ),
            .navigate => router.navigate(
              NamedRoute(
                isStack ? 'AccountRoute' : 'HomeRoute',
                children: [
                  if (isStack)
                    const NamedRoute('OrdersRoute')
                  else
                    const NamedRoute(
                      'ProfileTab',
                      children: [NamedRoute('OrdersRoute')],
                    ),
                ],
              ),
            ),
          };
          unawaited(navigation.then((_) => isDone = true));
          await tester.pumpAndSettle();

          expect(_guard.askCount, 1);
          expect(isDone, isFalse, reason: 'the guard still waits');

          if (!isYes) {
            await _guard.last.reject();
            await tester.pumpAndSettle();
            expect(isDone, isTrue, reason: 'the guard said no');
            expect(find.text('Orders'), findsNothing);
          } else {
            await _guard.last.allow();
            await tester.pumpAndSettle();
            expect(find.text('Orders'), findsOneWidget);
            expect(isDone, isFalse, reason: 'Orders is open');
            // The stack page is new: its call answers when it closes.
            if (!isStack) {
              tabs.stackRouterOfIndex(1)!.pop();
              await tester.pumpAndSettle();
              expect(isDone, isTrue, reason: 'Orders closed');
            }
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
