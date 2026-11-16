import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page stayed open for a signed-out user when a tab's guard signed the
// user out itself. Found by the orchestrator's final check of batch 3: a
// regression from 7d224e8d against dev 921fce58, the review's finding E.
// Setup: Home, Dashboard, whose guard turns signed-out users away, and a
// tabs page on its Profile tab. Profile's guard signs the user out itself
// when the token is refused, then lets the tab show. The session is the
// reevaluateListenable.
// Steps: the token is refused and the listenable notifies.
// Was: Dashboard was asked once, before the sign-out, and stayed open.
// 7d224e8d made a tab's guard's own change ask nothing again, also in a
// round's first pass, so the guards asked before it were not asked again.
// Should: Dashboard is asked again and closes, as when a stack page's guard
// makes the same change; the guard that made it is still asked a bounded
// number of times. This is the package's own rule, as before the batch: a
// guard round has no native counterpart, and dev 921fce58 is the reference.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;
  bool isTokenRefused = false;

  void signOut() {
    isSignedIn = false;
    notifyListeners();
  }

  void refuseToken() {
    isTokenRefused = true;
    notifyListeners();
  }
}

// Where the guard that signs the user out sits: on a tab of each kind of
// tabs widget, or on a page of the root stack.
enum _Host { tabs, pageView, tabBar, builder, scaffold, stackPage }

const List<PageRouteInfo> _tabRoutes = [
  NamedRoute('FeedTab'),
  NamedRoute('ProfileTab'),
];

Widget _tabsOf(_Host host) => switch (host) {
  .tabs => const AutoTabsRouter(routes: _tabRoutes),
  .pageView => const AutoTabsRouter.pageView(routes: _tabRoutes),
  .tabBar => const AutoTabsRouter.tabBar(routes: _tabRoutes),
  .builder => AutoTabsRouter.builder(
    routes: _tabRoutes,
    builder: (_, children, tabsRouter) =>
        IndexedStack(index: tabsRouter.activeIndex, children: children),
  ),
  .scaffold => const AutoTabsScaffold(routes: _tabRoutes),
  .stackPage => const SizedBox.shrink(),
};

NamedRouteDef _page(String name, String path, [AutoRouteGuard? guard]) => .new(
  name: name,
  path: path,
  guards: [?guard],
  builder: (_, _) => Text(name),
);

String _names(StackRouter? router) =>
    router?.stack.map((page) => page.routeData.name).join(', ') ?? 'none';

void main() {
  late _Session session;
  late int ownAsks;
  // What the session said each time the guard under the host was asked.
  late List<bool> belowSeen;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
    ownAsks = 0;
    belowSeen = [];
  });

  // The guard that signs the user out when the token is refused. With
  // [hold], its first ask reads the token, then waits for [hold] before it
  // acts on what it read.
  AutoRouteGuard ownGuard({Completer<void>? hold}) =>
      .simple((resolver, _) async {
        ownAsks++;
        final isRefused = session.isTokenRefused;
        if (ownAsks > 1 && hold != null && !hold.isCompleted) {
          await hold.future;
        }
        if (isRefused && session.isSignedIn) session.signOut();
        resolver.next();
      });

  // A guard that turns signed-out users away.
  AutoRouteGuard turnsAway() => .simple((resolver, _) {
    belowSeen.add(session.isSignedIn);
    session.isSignedIn ? resolver.next() : resolver.reject();
  });

  // A guard that, for a signed-out user, returns without an answer, and so
  // lets go of its page.
  AutoRouteGuard letsGo() => .simple((resolver, _) {
    belowSeen.add(session.isSignedIn);
    if (session.isSignedIn) resolver.next();
  });

  // The guard host's routes: a tabs page with the guard on its Profile tab,
  // or a page with the guard on it.
  NamedRouteDef hostRoute(_Host host, AutoRouteGuard own) => host == .stackPage
      ? _page('AccountRoute', '/account', own)
      : .new(
          name: 'TabsHostRoute',
          path: '/tabs',
          builder: (_, _) => Scaffold(body: _tabsOf(host)),
          children: [
            _page('FeedTab', 'feed'),
            _page('ProfileTab', 'profile', own),
          ],
        );

  // Opens the host on the top of [router]'s stack, on its guarded tab.
  Future<void> openHost(
    WidgetTester tester,
    RootStackRouter router,
    _Host host,
  ) async {
    final name = host == .stackPage ? 'AccountRoute' : 'TabsHostRoute';
    unawaited(router.push(NamedRoute(name)));
    await tester.pumpAndSettle();
    router.innerRouterOf<TabsRouter>('TabsHostRoute')?.setActiveIndex(1);
    await tester.pumpAndSettle();
  }

  for (final host in _Host.values) {
    group('With the guard on ${host.name}', () {
      testWidgets('its own sign-out in a first round closes a page under it '
          'whose guard turns signed-out users away', (tester) async {
        final router = RootStackRouter.build(
          routes: [
            _page('HomeRoute', '/'),
            _page('DashboardRoute', '/dashboard', turnsAway()),
            hostRoute(host, ownGuard()),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.push(const NamedRoute('DashboardRoute')));
        await tester.pumpAndSettle();
        await openHost(tester, router, host);
        final asksBefore = ownAsks;
        belowSeen.clear();

        session.refuseToken();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          (_names(router), session.isSignedIn, belowSeen.join(', ')),
          ('HomeRoute', false, 'true, false'),
        );
        expect(ownAsks - asksBefore, lessThanOrEqualTo(2));
        expect(find.text('HomeRoute'), findsOneWidget);
      });

      // The README: a change a guard makes itself during an extra round
      // isn't followed by another, so a guard that notifies the listenable
      // from its own check doesn't run without end. The same for each host.
      testWidgets('its own sign-out in a later round asks nothing again, as '
          "for a page's guard", (tester) async {
        final hold = Completer<void>();
        final router = RootStackRouter.build(
          routes: [
            _page('HomeRoute', '/'),
            _page('DashboardRoute', '/dashboard', turnsAway()),
            hostRoute(host, ownGuard(hold: hold)),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.push(const NamedRoute('DashboardRoute')));
        await tester.pumpAndSettle();
        await openHost(tester, router, host);
        belowSeen.clear();

        // A first round asks the guard, which reads a good token and waits.
        // The token is refused meanwhile, so a second round follows, in
        // which the guard reads it and signs the user out.
        unawaited(router.reevaluateGuards());
        await tester.pump();
        session.refuseToken();
        await tester.pumpAndSettle();
        hold.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final top = host == .stackPage ? 'AccountRoute' : 'TabsHostRoute';
        expect(
          (_names(router), session.isSignedIn, belowSeen.join(', ')),
          ('HomeRoute, DashboardRoute, $top', false, 'true, true'),
        );
      });

      testWidgets('its own sign-out lets go of a page under it whose guard '
          'then returns without an answer', (tester) async {
        final router = RootStackRouter.build(
          routes: [
            _page('HomeRoute', '/'),
            _page('NotesRoute', '/notes', letsGo()),
            hostRoute(host, ownGuard()),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.push(const NamedRoute('NotesRoute')));
        await tester.pumpAndSettle();
        await openHost(tester, router, host);
        belowSeen.clear();

        session.refuseToken();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          (_names(router), session.isSignedIn, belowSeen.join(', ')),
          ('HomeRoute', false, 'true, false'),
        );
        expect(find.text('HomeRoute'), findsOneWidget);
      });

      testWidgets("its own sign-out closes a nested router's page under it "
          'whose guard turns signed-out users away', (tester) async {
        final router = RootStackRouter.build(
          routes: [
            _page('HomeRoute', '/'),
            NamedRouteDef(
              name: 'ShellRoute',
              path: '/shell',
              builder: (_, _) => const AutoRouter(),
              children: [
                _page('OverviewRoute', ''),
                _page('DashboardRoute', 'dashboard', turnsAway()),
              ],
            ),
            hostRoute(host, ownGuard()),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.push(const NamedRoute('ShellRoute')));
        await tester.pumpAndSettle();
        final shell = router.innerRouterOf<StackRouter>('ShellRoute');
        unawaited(shell?.push(const NamedRoute('DashboardRoute')));
        await tester.pumpAndSettle();
        await openHost(tester, router, host);
        belowSeen.clear();

        session.refuseToken();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Asked before the sign-out with a yes, then again with a no, or,
        // where the nested router is asked after the page that signs out,
        // once with a no.
        expect(
          (_names(shell), session.isSignedIn, belowSeen.lastOrNull),
          ('OverviewRoute', false, false),
        );
      });
    });
  }
}
