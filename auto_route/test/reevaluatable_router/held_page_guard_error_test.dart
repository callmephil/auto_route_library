import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The error a held page's guard threw escaped reevaluateGuards() as an
// uncaught error. Fixes callmephil/auto_route_library#5.
// Setup: Home, Account and Details. Account's guard throws once the token
// store is closed, lets a signed-in user through, and returns without an
// answer for the others. The session is the router's reevaluateListenable.
// Steps: the app pushes Account. The user signs out: Account is held off
// the screen until its guard answers. The token store closes. The app
// awaits reevaluateGuards() in a try block. Then it pushes Details.
// Was: the catch block got nothing; the StateError reached the zone as an
// uncaught error. _composeMatchesForReevaluate asked each guard of
// _guardsLettingGo with unawaited(resolver.checkGuard(...)), so its error
// reached no caller.
// Should: reevaluateGuards() completes with the guard's error, the error
// does not also reach the zone, and the router works as before. An error
// report is not navigation behavior: no native source applies. It holds to
// what reevaluateGuards() already does for the guard of a page on the
// stack, which throws through that future.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  // From when on the guard throws, as one whose token store closed does.
  final ValueNotifier<bool> isStoreClosed = .new(false);

  @override
  void dispose() {
    isStoreClosed.dispose();
    super.dispose();
  }

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

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  for (final isAsync in [false, true]) {
    final kind = isAsync ? 'an async' : 'a';
    testWidgets('reevaluateGuards() completes with the error $kind guard of '
        'a held page throws', (tester) async {
      void check(NavigationResolver resolver) {
        if (session.isStoreClosed.value) {
          throw StateError('token store closed');
        }
        if (session.isSignedIn) resolver.next();
      }

      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page(
            'AccountRoute',
            '/account',
            guard: isAsync
                ? AutoRouteGuard.simple((resolver, _) async => check(resolver))
                : AutoRouteGuard.simple((resolver, _) => check(resolver)),
          ),
          page('DetailsRoute', '/details'),
        ],
      );
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.push(const NamedRoute('AccountRoute')));
        await tester.pumpAndSettle();
        session.set(signedIn: false);
        await tester.pumpAndSettle();

        session.isStoreClosed.value = true;
        await expectLater(router.reevaluateGuards(), throwsStateError);
        await tester.pumpAndSettle();
      }, (error, _) => uncaught.add(error));
      final afterError = names(router);
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(uncaught, isEmpty);
      expect(afterError, ['HomeRoute']);
      expect(names(router), ['HomeRoute', 'DetailsRoute']);
    });
  }
}
