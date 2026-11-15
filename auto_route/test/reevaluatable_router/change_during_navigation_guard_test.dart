import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page opened for a signed-out user when the session ended while the
// page's guard still waited. A lead of the audit of auto_route/lib, set
// aside in its second round; on dev too.
// Setup: Home, and Account behind an async guard that reads the session and
// then waits, as one that sends the token it read with a request does. The
// session is the router's reevaluateListenable.
// Steps: signed in, push(AccountRoute()). While the guard waits, the session
// ends and the listenable notifies. The guard's request comes back.
// Was: Account opened, and its guard was not asked again until the next
// change. The reevaluation the change started waited for the guard's call
// in flight and took its answer, from before the change, as its own.
// Should: the guard is asked once more before its page goes in, and rejects.
// The last change wins: Flutter's Router drops the answer of an older route
// parse when newer route information arrives and works on the newest
// (_currentRouterTransaction in widgets/router.dart), and on the web a
// navigation still in flight is canceled by the next one.
void main() {
  late ValueNotifier<bool> isSignedIn;
  // The requests the guard waits for, one per call, in order.
  late List<Completer<void>> requests;
  late int guardCalls;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    requests = [];
    guardCalls = 0;
  });

  // Reads the session, waits for its request when there is one, and answers
  // from what it read.
  final sessionGuard = AutoRouteGuard.simple((resolver, _) async {
    guardCalls++;
    final wasSignedIn = isSignedIn.value;
    if (requests.isNotEmpty) await requests.removeAt(0).future;
    wasSignedIn ? resolver.next() : resolver.reject();
  });

  AutoRoute page(
    String name,
    String path, {
    AutoRouteGuard? guard,
    List<AutoRoute>? children,
  }) => .new(
    page: PageInfo(
      name,
      builder: (_) =>
          children == null ? Scaffold(body: Text(name)) : const AutoRouter(),
    ),
    path: path,
    guards: [?guard],
    children: children,
  );

  RootStackRouter buildRouter({AutoRouteGuard? accountGuard}) => .build(
    routes: [
      page('HomeRoute', '/'),
      page('AccountRoute', '/account', guard: accountGuard ?? sessionGuard),
      page('BillsRoute', '/bills'),
      page(
        'ShellRoute',
        '/shell',
        children: [
          page('ListRoute', ''),
          page('DetailRoute', 'detail', guard: sessionGuard),
        ],
      ),
    ],
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Has the next guard call wait for a request, and returns the request.
  Completer<void> nextRequest() {
    final request = Completer<void>();
    requests.add(request);
    return request;
  }

  final calls =
      <String, Future<void> Function(StackRouter, OnNavigationFailure)>{
        'push': (router, onFailure) =>
            router.push(const NamedRoute('AccountRoute'), onFailure: onFailure),
        'replace': (router, onFailure) => router.replace(
          const NamedRoute('AccountRoute'),
          onFailure: onFailure,
        ),
        'pushAll': (router, onFailure) => router.pushAll([
          const NamedRoute('BillsRoute'),
          const NamedRoute('AccountRoute'),
        ], onFailure: onFailure),
        'replaceAll': (router, onFailure) => router.replaceAll([
          const NamedRoute('AccountRoute'),
        ], onFailure: onFailure),
        'navigate': (router, onFailure) => router.navigate(
          const NamedRoute('AccountRoute'),
          onFailure: onFailure,
        ),
      };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    for (final isFrameApart in [true, false]) {
      final moment = isFrameApart ? 'a frame after' : 'in the turn of';
      testWidgets('A sign-out $moment a $name whose guard waits never opens '
          'the guarded page', (tester) async {
        final router = buildRouter();
        await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
        final request = nextRequest();
        final failures = <NavigationFailure>[];

        unawaited(call(router, failures.add));
        if (isFrameApart) await tester.pump();
        isSignedIn.value = false;
        await tester.pump();
        request.complete();
        await tester.pumpAndSettle();

        expect(stackNames(router), ['HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(guardCalls, 2);
        expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      });
    }
  }

  testWidgets('A sign-out while the guard of a push in a nested router waits '
      'never opens the guarded page', (tester) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    unawaited(router.push(const NamedRoute('ShellRoute')));
    await tester.pumpAndSettle();
    final shell = router.innerRouterOf<StackRouter>('ShellRoute');
    final request = nextRequest();
    final failures = <NavigationFailure>[];

    unawaited(
      shell?.push(const NamedRoute('DetailRoute'), onFailure: failures.add),
    );
    await tester.pump();
    isSignedIn.value = false;
    await tester.pump();
    request.complete();
    await tester.pumpAndSettle();

    expect(shell == null ? null : stackNames(shell), ['ListRoute']);
    expect(find.text('ListRoute'), findsOneWidget);
    expect(guardCalls, 2);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  // The change left the guard's answer as it was, as a refreshed token does.
  testWidgets('A change while the guard of a push waits that keeps the user '
      'signed in opens the page once', (tester) async {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    final router = buildRouter();
    await pumpRouterApp(tester, router, reevaluationNotifier: changes);
    final request = nextRequest();

    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pump();
    changes.value++;
    await tester.pump();
    request.complete();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(guardCalls, 2);
  });

  // The guard signs the user in itself and notifies, as one that restores a
  // stored session does: its answer is from after its own change.
  testWidgets('A guard of a push that changes the session itself is asked '
      'once', (tester) async {
    isSignedIn.value = false;
    final router = buildRouter(
      accountGuard: AutoRouteGuard.simple((resolver, _) async {
        guardCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        isSignedIn.value = true;
        resolver.next();
      }),
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);

    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    final callsOfPush = guardCalls;

    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(callsOfPush, 1);
  });

  // The guard shows a login page of its own and awaits it. The user signs
  // in there, which changes the session through code of the app: the guard
  // answers from what happened on its page, after the change.
  testWidgets('A guard of a push that awaits its own login page is asked '
      'once when the user signs in there', (tester) async {
    isSignedIn.value = false;
    final router = buildRouter(
      accountGuard: AutoRouteGuard.simple((resolver, guarded) async {
        guardCalls++;
        final didSignIn = await guarded.push<bool>(
          const NamedRoute('BillsRoute'),
        );
        (didSignIn ?? false) ? resolver.next() : resolver.reject();
      }),
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);

    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    final atLogin = stackNames(router);
    isSignedIn.value = true;
    await tester.pump();
    unawaited(router.maybePop(true));
    await tester.pumpAndSettle();

    expect(atLogin, ['HomeRoute', 'BillsRoute']);
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(guardCalls, 1);
  });

  // The guard's check changes the session through code of the app, here in
  // the zone of the test as a stream's listener set up at the app's start
  // runs in the app's: the router can't tell that change from one outside
  // the guard.
  testWidgets('A guard of a push whose every check changes the session '
      'through the app is asked a bounded number of times', (tester) async {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    final appZone = Zone.current;
    final router = buildRouter(
      accountGuard: AutoRouteGuard.simple((resolver, _) async {
        guardCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        appZone.run(() => changes.value++);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        resolver.next();
      }),
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: changes);

    unawaited(router.push(const NamedRoute('AccountRoute')));
    // No frame is scheduled while a guard waits on its timers.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    final callsOfPush = guardCalls;

    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(callsOfPush, 4);
  });
}
