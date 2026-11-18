import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab's guard ran at each later change after the user closed its tabs
// page. Fixes callmephil/auto_route_library#2.
// Setup: Home and a tabs page Tabs with the tabs Feed and Profile.
// Profile's guard lets a signed-in user through and returns without an
// answer for the others. The session is the router's reevaluateListenable.
// Steps: the app pushes Tabs and the user selects Profile. The user signs
// out: the guard returns without an answer, so Feed shows until it
// answers. The user closes Tabs. The session notifies three times, then the
// earlier call of the guard says yes.
// Was: each notification called Profile's guard again, for a tab that was
// gone. The guard's entry stayed in _guardsLettingGo of the stack router
// above the tabs until the guard answered, and that router never learned
// that the tabs router was disposed.
// Should: once Tabs closes, no change calls the guard, and its later yes
// opens nothing: Home stays alone.
// Native behavior this holds to: Flutter's Navigator completes and disposes
// a route that leaves the stack (_RouteEntry.handleComplete and finalize,
// navigator.dart, Flutter 3.50.0); nothing of it runs afterwards.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void set({required bool signedIn}) {
    isSignedIn = signedIn;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

void main() {
  late _Session session;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
  });

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Text(name),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('No change asks the guard of a held tab once its tabs page '
      'closed', (tester) async {
    var asks = 0;
    final answers = <NavigationResolver>[];
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
        ),
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/tabs',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [NamedRoute('FeedRoute'), NamedRoute('ProfileRoute')],
            ),
          ),
          children: [
            page('FeedRoute', 'feed'),
            page(
              'ProfileRoute',
              'profile',
              guard: AutoRouteGuard.simple((resolver, _) {
                asks++;
                answers.add(resolver);
                if (session.isSignedIn) resolver.next();
              }),
            ),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    unawaited(router.push(const NamedRoute('TabsRoute')));
    await tester.pumpAndSettle();
    router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
    await tester.pumpAndSettle();
    session.set(signedIn: false);
    await tester.pumpAndSettle();
    final shownAfterSignOut = find.text('FeedRoute').evaluate().length;

    await router.maybePop();
    await tester.pumpAndSettle();
    asks = 0;
    for (var times = 0; times < 3; times++) {
      session.refresh();
      await tester.pumpAndSettle();
    }
    final asksAfterClose = asks;
    for (final resolver in answers) {
      if (!resolver.isResolved) resolver.next();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shownAfterSignOut, 1);
    expect(asksAfterClose, 0);
    expect(names(router), ['HomeRoute']);
    expect(find.text('ProfileRoute'), findsNothing);
  });
}
