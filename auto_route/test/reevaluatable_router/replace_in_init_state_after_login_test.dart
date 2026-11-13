import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../named_page.dart';
import '../router_test_utils.dart';
import 'auth_state.dart';

// A page that was replaced right after the reevaluate listenable changed
// came back under its replacement when the two were called while widgets
// are built. The replace then starts a microtask later, and landed between
// the moment the reevaluation had collected the pages and the moment it put
// each back, a microtask after its guards had answered.
// Steps: the auth state is the router's reevaluateListenable. The app opens
// on a splash page whose initState signs the user in, which notifies the
// listenable, and then calls replace(DashboardRoute) or
// replaceAll([DashboardRoute]).
// Was: [Splash, Dashboard] when Dashboard has no guard. With a guard that
// answers at once it was [Dashboard], only because the replace then took a
// few microtasks more.
// Should: [Dashboard], with or without the guard.
// Native behavior this holds to: Flutter's Navigator keeps a route off once
// pushReplacement has taken it off; nothing brings it back.
void main() {
  const dashboard = NamedRoute('DashboardRoute');
  final replacements = <String, void Function(StackRouter router)>{
    'replace': (router) => unawaited(router.replace(dashboard)),
    'replaceAll': (router) => unawaited(router.replaceAll([dashboard])),
  };

  for (final MapEntry(key: name, value: replaceSplash)
      in replacements.entries) {
    for (final isGuarded in [false, true]) {
      testWidgets('$name in the initState that signs in leaves the new page '
          'alone, guarded: $isGuarded', (tester) async {
        final auth = AuthState();
        addTearDown(auth.dispose);
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'SplashRoute',
              path: '/',
              builder: (_, _) => _SignsInAtStart(auth, replaceSplash),
            ),
            NamedRouteDef(
              name: 'DashboardRoute',
              path: '/dashboard',
              guards: [
                if (isGuarded)
                  AutoRouteGuard.simple(
                    (resolver, _) =>
                        auth.isLoggedIn ? resolver.next() : resolver.reject(),
                  ),
              ],
              builder: (_, _) => const NamedPage('DashboardRoute'),
            ),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: auth);

        expect(tester.takeException(), isNull);
        expect(router.stack.map((page) => page.name), ['DashboardRoute']);
        expect(find.text('DashboardRoute'), findsOneWidget);
      });
    }
  }
}

class _SignsInAtStart extends StatefulWidget {
  const new(this._auth, this._replaceSplash);

  final AuthState _auth;
  final void Function(StackRouter router) _replaceSplash;

  @override
  State<_SignsInAtStart> createState() => _SignsInAtStartState();
}

class _SignsInAtStartState extends State<_SignsInAtStart> {
  @override
  void initState() {
    super.initState();
    widget._auth.isLoggedIn = true;
    widget._replaceSplash(context.router);
  }

  @override
  Widget build(BuildContext context) => const NamedPage('SplashRoute');
}
