import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The pages above a page that reevaluateGuards() closed reported popped,
// not removed. Fixes callmephil/auto_route_library#10.
// Setup: Home, Account and Settings. Account's guard lets a signed-in user
// through; for the others it rejects, or returns without an answer. The
// content of Account and Settings records each kind its
// AutoRouteLeaveListener hears. The session is the router's
// reevaluateListenable.
// Steps: the app pushes Account, then Settings. The user signs out.
// Was: Account heard removed, Settings heard popped. The rejection branch
// of _pushAllGuarded marked only the rejected page as removed; the pages
// above it left with the default kind.
// Should: each page that leaves because a guard on reevaluateGuards()
// closes it, or a page below it, hears removed, for a rejected page as for
// a held one. The pages above still leave with it, as Android's
// popBackStack(destinationId, inclusive = true) removes every destination
// above the one it names.
// Native behavior this holds to: on Android, iOS and the web, a pop is a
// back action of the user or a pop call of the app. Here a guard closes the
// pages, so no pop occurs, and the kind is removed, as the doc of
// RouteLeaveKind.removed says.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void set({required bool signedIn}) {
    isSignedIn = signedIn;
    notifyListeners();
  }
}

void main() {
  late _Session session;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
  });

  for (final rejects in [true, false]) {
    final answer = rejects ? 'rejects' : 'returns without an answer';
    testWidgets('Each page that leaves when the guard below it $answer '
        'hears removed', (tester) async {
      final heard = <String>[];
      NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) =>
          .new(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => AutoRouteLeaveListener(
              onLeave: (kind) => heard.add('$name ${kind.name}'),
              child: Scaffold(body: Text(name)),
            ),
          );
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
          ),
          page(
            'AccountRoute',
            '/account',
            guard: AutoRouteGuard.simple((resolver, _) {
              if (session.isSignedIn) return resolver.next();
              if (rejects) resolver.reject();
            }),
          ),
          page('SettingsRoute', '/settings'),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();
      heard.clear();

      session.set(signedIn: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.routeData.name), ['HomeRoute']);
      expect(
        heard,
        unorderedEquals(['AccountRoute removed', 'SettingsRoute removed']),
      );
    });
  }
}
