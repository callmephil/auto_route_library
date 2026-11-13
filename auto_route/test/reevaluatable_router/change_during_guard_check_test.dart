import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page stayed open after its guard would close it, when the state the guard
// reads changed twice in a row. Found by the audit of auto_route/lib at dev
// 56b73492 (finding C7).
// Steps: Home and Account, behind an async guard that reads the session and
// then waits, as one that awaits a request does. The reevaluateListenable
// notifies while the session is still valid; while that reevaluation waits on
// the guard, the session ends and the listenable notifies again.
// Was: Account stayed open. The second reevaluation never asked the guard
// again: it waited for the guard's call in flight and took that answer, from
// before the second change, as its own.
// Should: the last change wins, so Account closes. A change notification
// means "look again": Flutter's Router drops the answer of an older route
// parse when newer route information arrives and works on the newest
// (_currentRouterTransaction in widgets/router.dart).
void main() {
  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  NamedRouteDef plainRoute(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => page(name),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('A change while a guard runs its check is followed by another '
      'reevaluation', (tester) async {
    final isSessionValid = ValueNotifier(true);
    addTearDown(isSessionValid.dispose);
    final waits = <Completer<void>>[];
    final session = ValueNotifier(0);
    addTearDown(session.dispose);
    final router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute(
          'AccountRoute',
          '/account',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              final wasValid = isSessionValid.value;
              if (waits.isNotEmpty) await waits.removeAt(0).future;
              if (wasValid) {
                resolver.next();
              } else {
                resolver.reject();
              }
            }),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(
      tester,
      router.config(reevaluateListenable: session),
    );
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);

    // First change: the session is still valid, and the guard takes its time.
    final slow = Completer<void>();
    waits.add(slow);
    session.value++;
    await tester.pump();
    // Second change, while the first reevaluation waits: the session ended.
    isSessionValid.value = false;
    session.value++;
    await tester.pump();
    final topWhileChecking = router.current.name;
    slow.complete();
    await tester.pumpAndSettle();

    expect(topWhileChecking, 'AccountRoute');
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('AccountRoute'), findsNothing);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  // A guard that notifies the listenable from its own check, as one that
  // refreshes the session does, would be asked without end if every change
  // during a reevaluation were followed by another one.
  testWidgets('A guard that notifies the listenable on every check is asked '
      'a bounded number of times', (tester) async {
    var guardCalls = 0;
    final session = ValueNotifier(0);
    addTearDown(session.dispose);
    final router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute(
          'AccountRoute',
          '/account',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              guardCalls++;
              await Future<void>.delayed(const Duration(milliseconds: 10));
              session.value++;
              resolver.next();
            }),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(
      tester,
      router.config(reevaluateListenable: session),
    );
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    final stackAtFirst = stackNames(router);

    guardCalls = 0;
    session.value++;
    await tester.pumpAndSettle();

    expect(stackAtFirst, ['HomeRoute', 'AccountRoute']);
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    // The check the change started, and the one that follows its own
    // notification.
    expect(guardCalls, 2);
  });
}
