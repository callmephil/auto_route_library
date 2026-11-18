import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// callmephil/auto_route_library#7: navigatePath into the nested router of
// a tab completes only once the guards there have answered.
// Steps: Home shows its tabs Feed and Profile; Profile holds a stack router
// with ProfileHome and Orders, whose guard waits for the test. The app
// awaits navigatePath('/profile/orders'). The guard says no; then, on a
// second navigatePath, yes, and Orders closes.
// Was: the future completed at once, while the guard still waited.
// Should: the future waits for the no, and after the yes for Orders to
// close.
// Native behavior this holds to: Flutter's Router awaits the delegate's
// setNewRoutePath before it rebuilds.
// Headless test:
// auto_route/test/nested_tabs_router/navigation_into_tab_waits_for_nested_guards_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => SafeArea(child: Center(child: Text(name)));

  group('navigation into tab waits for nested guards', () {
    testWidgets('navigatePath into a tab waits for the guard of Orders', (
      tester,
    ) async {
      var answer = Completer<bool>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter(
                routes: [NamedRoute('FeedTab'), NamedRoute('ProfileTab')],
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'FeedTab',
                path: 'feed',
                builder: (_, _) => page('Feed'),
              ),
              NamedRouteDef(
                name: 'ProfileTab',
                path: 'profile',
                builder: (_, _) => const AutoRouter(),
                children: [
                  NamedRouteDef(
                    name: 'ProfileHomeRoute',
                    path: '',
                    builder: (_, _) => page('ProfileHome'),
                  ),
                  NamedRouteDef(
                    name: 'OrdersRoute',
                    path: 'orders',
                    guards: [
                      AutoRouteGuard.simple(
                        (resolver, _) async => await answer.future
                            ? resolver.next()
                            : resolver.reject(),
                      ),
                    ],
                    builder: (_, _) => page('Orders'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      var isDone = false;
      unawaited(
        router.navigatePath('/profile/orders').then((_) => isDone = true),
      );
      await tester.pumpAndSettle();
      expect(isDone, isFalse, reason: 'the guard waits');

      answer.complete(false);
      await tester.pumpAndSettle();
      expect(isDone, isTrue, reason: 'the guard said no');
      expect(find.text('Orders'), findsNothing);

      answer = Completer<bool>();
      var isSecondDone = false;
      unawaited(
        router.navigatePath('/profile/orders').then((_) => isSecondDone = true),
      );
      await tester.pumpAndSettle();
      expect(isSecondDone, isFalse, reason: 'the guard waits');
      answer.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Orders'), findsOneWidget);
      expect(isSecondDone, isFalse, reason: 'Orders is open');

      router
          .innerRouterOf<TabsRouter>('HomeRoute')!
          .stackRouterOfIndex(1)!
          .pop();
      await tester.pumpAndSettle();
      expect(isSecondDone, isTrue, reason: 'Orders closed');
      expect(tester.takeException(), isNull);
    });
  });
}
