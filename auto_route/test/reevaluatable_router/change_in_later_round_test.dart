import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page stayed open for a signed-out user when the session ended as the
// third of three changes in a row. A lead of the audit of auto_route/lib,
// left by its fix for two changes in a row (C7).
// Setup: Home and Account, behind an async guard that reads the session and
// then waits, as one that sends the token it read with a request does. The
// router's reevaluateListenable notifies on every change of the session.
// Steps: the token is refreshed, and the guard is asked again and waits. The
// token is refreshed once more, so the guards are asked again once that
// round ends. In that second round, while the guard waits, the session ends.
// Was: Account stayed open. Only a change in the first round was followed
// by another round, so that a guard which notifies the listenable from its
// own check is not asked without end; the third change took the second
// round's answer, from before it.
// Should: Account closes. A change that is not the guard's own is followed
// by another round also in a later round; a guard's own change still is not.
// The last change wins: Flutter's Router drops the answer of an older route
// parse when newer route information arrives and works on the newest
// (_currentRouterTransaction in widgets/router.dart).
void main() {
  late ValueNotifier<bool> isSignedIn;
  late ValueNotifier<int> changes;
  // The requests the guard waits for, one per call, in order.
  late List<Completer<void>> requests;
  late int guardCalls;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    requests = [];
    guardCalls = 0;
  });

  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Lets the timers a guard waits on run out, round after round, as no
  // frame is scheduled while a guard waits.
  Future<void> pumpWhileGuardsWait(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  // Opens Home and Account, behind [guard] or a guard that reads the
  // session, waits for its request when there is one, and answers from what
  // it read.
  Future<RootStackRouter> openAccount(
    WidgetTester tester, {
    AutoRouteGuard? guard,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          guard ??
              AutoRouteGuard.simple((resolver, _) async {
                guardCalls++;
                final wasSignedIn = isSignedIn.value;
                if (requests.isNotEmpty) await requests.removeAt(0).future;
                wasSignedIn ? resolver.next() : resolver.reject();
              }),
        ),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: changes);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await pumpWhileGuardsWait(tester);
    guardCalls = 0;
    return router;
  }

  // Has the next guard call wait for a request, and returns the request.
  Completer<void> nextRequest() {
    final request = Completer<void>();
    requests.add(request);
    return request;
  }

  for (final rounds in [2, 3]) {
    testWidgets('A sign-out while the guard waits in round $rounds of its '
        'checks closes the page', (tester) async {
      final router = await openAccount(tester);
      final waiting = [for (var i = 0; i < rounds; i++) nextRequest()];

      // The token is refreshed: the first round begins.
      changes.value++;
      await tester.pump();
      // Each later round begins with a change during the round before it.
      for (final request in waiting.take(rounds - 1)) {
        changes.value++;
        await tester.pump();
        request.complete();
        await tester.pump();
        await tester.pump();
      }
      final callsBeforeSignOut = guardCalls;
      isSignedIn.value = false;
      changes.value++;
      await tester.pump();
      waiting.lastOrNull?.complete();
      await tester.pumpAndSettle();

      expect(callsBeforeSignOut, rounds);
      expect(stackNames(router), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(guardCalls, rounds + 1);
    });
  }

  // The guard's check changes the session through code of the app, here in
  // the zone of the test as a stream's listener set up at the app's start
  // runs in the app's: the router can't tell that change from one outside
  // the guard.
  testWidgets('A guard whose every check changes the session through the '
      'app is asked a bounded number of times', (tester) async {
    final appZone = Zone.current;
    final router = await openAccount(
      tester,
      guard: AutoRouteGuard.simple((resolver, _) async {
        guardCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        appZone.run(() => changes.value++);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        resolver.next();
      }),
    );

    changes.value++;
    await pumpWhileGuardsWait(tester);
    final callsOfChange = guardCalls;

    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    // The round the change started and three more.
    expect(callsOfChange, 4);
  });
}
