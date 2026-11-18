import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard asked again got the same resolver at each call, so a guard that
// answers each call once failed the assert that a resolver answers only
// once. Fixes callmephil/auto_route_library#4.
// Setup: Home and Account. Account's guard lets a signed-in user through.
// For the others it keeps one callback per call, which answers yes once
// the user has a session again. The session is the router's
// reevaluateListenable.
// Steps: the app pushes Account. The user signs out: the guard keeps its
// first callback, and Account is held off the screen until it answers.
// The session notifies two more times: a second and a third callback. The
// user signs in, and each callback is called.
// Was: the first callback opened Account, and each later one failed the
// assert (in a release build, a StateError from the completed Completer).
// NavigationResolver.checkGuard called the guard again with the same
// resolver, and its answer methods assert that it has not answered.
// Should: each call gets a resolver of its own. Only the answer of the
// latest call decides; a later answer of an earlier call is ignored. So
// Account opens once, and nothing throws.
// Native behavior this holds to: Flutter's Router ignores the result of an
// older route transaction when a newer one started
// (_processParsedRouteInformation, router.dart, Flutter 3.50.0).
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

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  RootStackRouter buildRouter(List<VoidCallback> callbacks) => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
      ),
      NamedRouteDef(
        name: 'AccountRoute',
        path: '/account',
        guards: [
          AutoRouteGuard.simple((resolver, _) {
            if (session.isSignedIn) return resolver.next();
            // Answers when the user has a session again.
            callbacks.add(resolver.next);
          }),
        ],
        builder: (_, _) => const Scaffold(body: Text('AccountRoute')),
      ),
    ],
  );

  Future<void> signOutThreeTimes(WidgetTester tester) async {
    session.set(signedIn: false);
    await tester.pumpAndSettle();
    session.refresh();
    await tester.pumpAndSettle();
    session.refresh();
    await tester.pumpAndSettle();
  }

  for (final isOldestFirst in [true, false]) {
    final order = isOldestFirst ? 'oldest first' : 'newest first';
    testWidgets('A guard that answers each of its calls once never fails, '
        'and Account opens once ($order)', (tester) async {
      final callbacks = <VoidCallback>[];
      final router = buildRouter(callbacks);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      await signOutThreeTimes(tester);
      final stackWhileHeld = names(router);
      final callsWhileHeld = callbacks.length;

      session.isSignedIn = true;
      final errors = <Object>[];
      for (final callback in isOldestFirst ? callbacks : callbacks.reversed) {
        try {
          callback();
        } on Object catch (error) {
          errors.add(error);
        }
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
      expect(errors, isEmpty);
      expect(stackWhileHeld, ['HomeRoute']);
      expect(callsWhileHeld, 3);
      expect(names(router), ['HomeRoute', 'AccountRoute']);
      expect(find.text('AccountRoute'), findsOneWidget);
    });
  }

  testWidgets('Only the latest call decides: an earlier call answering '
      'alone opens nothing', (tester) async {
    final callbacks = <VoidCallback>[];
    final router = buildRouter(callbacks);
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    await signOutThreeTimes(tester);

    session.isSignedIn = true;
    callbacks.firstOrNull?.call();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(names(router), ['HomeRoute']);
  });

  testWidgets('A second answer from the same call still fails the assert', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
        ),
        NamedRouteDef(
          name: 'AccountRoute',
          path: '/account',
          guards: [
            AutoRouteGuard.simple((resolver, _) {
              resolver.next();
              if (kDebugMode) {
                expect(resolver.next, throwsAssertionError);
              }
            }),
          ],
          builder: (_, _) => const Scaffold(body: Text('AccountRoute')),
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(names(router), ['HomeRoute', 'AccountRoute']);
  });
}
