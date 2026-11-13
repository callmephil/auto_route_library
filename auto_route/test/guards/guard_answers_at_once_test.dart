import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import '../named_page.dart';
import '../router_test_utils.dart';

// A push whose guards answered in their own call, as a guard that reads a
// flag and calls next does, still added its page a microtask after the call.
// A navigation called right after it, with no await between them, acted on
// the stack without the page: from Home, push(A) then replace(B) gave [A, B]
// with a guard for every route, and [B, A] with a guard on A alone, where a
// route with no guard gives [Home, B].
// Steps, from [Home]: push(A) then replace(B) or removeLast(), with a guard in
// RootStackRouter.guards, with a guard on A, and with an async guard that
// answers before its first await.
// Native behavior this holds to: Flutter's Navigator changes its history as
// each call is made, so Navigator.push followed by pushReplacement replaces
// the route just pushed. A check that passes at once, such as the web's
// navigate event when no handler intercepts it, or shouldPerformSegue on iOS
// returning true, delays nothing: the navigation is done as the call returns.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  final lets = AutoRouteGuard.simple((resolver, _) => resolver.next());
  final letsBeforeItsFirstAwait = AutoRouteGuard.simple((resolver, _) async {
    resolver.next();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  final rejects = AutoRouteGuard.simple((resolver, _) => resolver.reject());
  final letsAfterAWait = AutoRouteGuard.simple((resolver, _) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    resolver.next();
  });

  Future<RootStackRouter> open(
    WidgetTester tester, {
    AutoRouteGuard? forEveryRoute,
    AutoRouteGuard? forA,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path, guard) in [
          ('HomeRoute', '/', null),
          ('ARoute', '/a', forA),
          ('BRoute', '/b', null),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => NamedPage(name),
          ),
      ],
      guards: [?forEveryRoute],
    );
    await pumpRouterConfigApp(tester, router.config());
    return router;
  }

  testWidgets('With a guard for every route that answers at once, a replace '
      'right after a push replaces the pushed page', (tester) async {
    final router = await open(tester, forEveryRoute: lets);

    unawaited(router.push(a));
    unawaited(router.replace(b));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'BRoute']);
    expect(find.text('BRoute'), findsOneWidget);
  });

  testWidgets('With a guard on the pushed route that answers at once, a '
      'replace right after the push replaces the pushed page', (tester) async {
    final router = await open(tester, forA: lets);

    unawaited(router.push(a));
    unawaited(router.replace(b));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'BRoute']);
    expect(find.text('BRoute'), findsOneWidget);
  });

  testWidgets('An async guard that answers before its first await delays '
      'nothing', (tester) async {
    final router = await open(tester, forA: letsBeforeItsFirstAwait);

    unawaited(router.push(a));
    unawaited(router.replace(b));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'BRoute']);
  });

  // Should: the page is on the stack as push returns, as with no guard, so
  // removeLast right after it removes that page.
  testWidgets('A page its guards let through at once is on the stack as '
      'push returns', (tester) async {
    final router = await open(tester, forEveryRoute: lets, forA: lets);

    unawaited(router.push(a));

    expect(stackNames(router), ['HomeRoute', 'ARoute']);
    expect(router.activeGuardObserver.guardInProgress, isFalse);

    router.removeLast();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  // Should: the rejection is known as push returns too, so the replace acts
  // on the stack as it was and takes the place of Home.
  testWidgets('A guard that rejects at once leaves the stack to the next '
      'call', (tester) async {
    final router = await open(tester, forA: rejects);
    final failures = <NavigationFailure>[];

    unawaited(router.push(a, onFailure: failures.add));

    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());

    unawaited(router.replace(b));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['BRoute']);
  });

  // A guard that awaits before it answers makes its push wait. A call made
  // meanwhile does not wait behind it, as pop doesn't: the guard may be
  // waiting on the very page the call closes.
  // Should: the replace takes the place of Home at once, and A goes on top
  // once its guard lets it through.
  testWidgets('A call right after a push whose guard awaits acts on the '
      'stack without the page', (tester) async {
    final router = await open(tester, forA: letsAfterAWait);

    unawaited(router.push(a));
    unawaited(router.replace(b));

    expect(stackNames(router), ['BRoute']);

    await tester.pumpAndSettle();

    expect(stackNames(router), ['BRoute', 'ARoute']);
    expect(find.text('ARoute'), findsOneWidget);
  });
}
