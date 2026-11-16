import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab's guard that changes the router's reevaluateListenable itself was
// asked without end. Found by the review of 80cee137 (its finding 7); on dev
// 921fce58 too.
// Setup: tabs Feed and Profile. Profile's guard awaits a token check; when
// the token is refused it signs the user out itself, then lets the tab show
// its signed-out view. The session is the reevaluateListenable.
// Steps: the user chooses Profile.
// Was: Profile's guard was asked 51 times in one settle. Each sign-out the
// guard made started a reevaluation, which asked the shown tab's guard
// again, which signed out again. A page's guard is asked again at most once
// after a change it makes itself (_askAgainAfterReevaluation), but a tab's
// ask was not taken for a reevaluation's, so its own change was not known.
// Should: asked for the change, then once by the reevaluation its sign-out
// starts, which finds the tab shown, as any reevaluation does; the change
// that ask makes itself asks it nothing again. A change that is not the
// guard's own, during that ask, still asks it again once the round ends.
// Native behavior this holds to: Flutter's Router handles each
// notification of its route information provider once, in one transaction,
// and starts nothing again by itself (_handleRouteInformationProviderNotification
// and _currentRouterTransaction, router.dart); the README: a guard that
// notifies the listenable from its own check doesn't run without end.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void signOut() {
    isSignedIn = false;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

void main() {
  late _Session session;
  late int asks;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
    asks = 0;
  });

  RootStackRouter buildRouter(AutoRouteGuard guard) => .build(
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
            builder: (_, _) => const Text('FeedTab'),
          ),
          NamedRouteDef(
            name: 'ProfileTab',
            path: 'profile',
            guards: [guard],
            builder: (_, _) => const Text('ProfileTab'),
          ),
        ],
      ),
    ],
  );

  testWidgets("A tab guard's own sign-out asks it nothing again", (
    tester,
  ) async {
    final router = buildRouter(
      AutoRouteGuard.simple((resolver, _) async {
        asks++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // The token was refused.
        session.signOut();
        resolver.next();
      }),
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect((asks, tabs.activeIndex), (2, 1));
    expect(find.text('ProfileTab'), findsOneWidget);
  });

  // Passes before the fix too.
  testWidgets("A change that is not the tab guard's own, during its ask by a "
      'reevaluation, asks it again', (tester) async {
    final checks = <Completer<void>>[];
    final router = buildRouter(
      AutoRouteGuard.simple((resolver, _) async {
        asks++;
        final check = Completer<void>();
        checks.add(check);
        await check.future;
        resolver.next();
      }),
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    checks.lastOrNull?.complete();
    await tester.pumpAndSettle();
    session.refresh();
    await tester.pumpAndSettle();
    final asksBeforeSecondChange = asks;

    session.refresh();
    await tester.pumpAndSettle();
    for (final check in checks) {
      if (!check.isCompleted) check.complete();
    }
    await tester.pumpAndSettle();
    for (final check in checks) {
      if (!check.isCompleted) check.complete();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(asks, greaterThan(asksBeforeSecondChange));
    expect(tabs.activeIndex, 1);
  });
}
