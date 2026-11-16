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
// Should: asked as often as a page's guard with the same check: for the
// change, then by the reevaluation its sign-out starts, which finds the tab
// shown, then once more by the round its own change in that reevaluation
// asks for, so the guards asked before it are asked again too (see
// tab_guard_own_change_asks_others_test.dart); its own change in that later
// round asks nothing again. A change that is not the guard's own, during
// its ask, still asks it again once the round ends. This is the package's
// own rule, as the README states it: a change a guard makes itself during
// an extra round isn't followed by another, so a guard that notifies the
// listenable from its own check doesn't run without end. A guard round has
// no native counterpart.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;
  bool isTokenRefused = false;

  void refuseToken() {
    isTokenRefused = true;
    notifyListeners();
  }

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
        name: 'AccountRoute',
        path: '/account',
        guards: [guard],
        builder: (_, _) => const Text('AccountRoute'),
      ),
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

  // Signs the user out on every ask once the token is refused.
  AutoRouteGuard signsOut() => .simple((resolver, _) async {
    asks++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (session.isTokenRefused) session.signOut();
    resolver.next();
  });

  // The count the tab's guard is held to: asked by the round the refused
  // token starts, then by the one its own sign-out there asks for.
  testWidgets("A page's guard that signs the user out on every ask is asked "
      'twice', (tester) async {
    final router = buildRouter(signsOut());
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    asks = 0;

    session.refuseToken();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(asks, 2);
  });

  testWidgets("A tab's guard that signs the user out on every ask is asked "
      "as often as a page's guard", (tester) async {
    final router = buildRouter(signsOut());
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    asks = 0;

    session.refuseToken();
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
