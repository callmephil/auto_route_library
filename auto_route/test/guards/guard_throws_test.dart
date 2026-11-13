import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard that threw once, as an async guard does when the request it awaits
// fails, broke the router for good. Found by the audit of auto_route/lib at
// dev 56b73492 (finding C2).
// Setup: Home, Account behind an async guard, and Other.
// 1. push(Account) while the guard throws.
//    Was: the push failed, as it should, but
//    activeGuardObserver.guardInProgress stayed true, so a loading overlay
//    tied to it never went, and every later reevaluateGuards() called the
//    guard again for that dead push.
// 2. With [Home, Account, Other] open, the guard throws during
//    reevaluateGuards().
//    Was: Account and Other left the stack, and no later reevaluation ran
//    the guards again, so a later sign-out closed nothing.
// 3. replaceAll([Account]), or pushAll([Other, Account]), while the guard
//    throws.
//    Was: replaceAll left the stack empty, a blank screen.
// Should: a check that fails leaves the navigation undone, and the router
// working. Flutter's Navigator.maybePop awaits the route's willPop and pops
// nothing when that throws; on the web a navigation whose handler rejects is
// canceled, with the url and the current entry as they were; Android's
// NavController.navigate leaves its back stack as it was when it throws.
void main() {
  late RootStackRouter router;
  late bool doesThrow;
  late bool isAllowed;
  late int guardCalls;

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

  setUp(() {
    doesThrow = false;
    isAllowed = true;
    guardCalls = 0;
    router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute(
          'AccountRoute',
          '/account',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              guardCalls++;
              await Future<void>.delayed(.zero);
              if (doesThrow) throw StateError('no network');
              if (isAllowed) {
                resolver.next();
              } else {
                resolver.reject();
              }
            }),
          ],
        ),
        plainRoute('OtherRoute', '/other'),
      ],
    );
  });

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  // The error [navigation] fails with, or null.
  Future<Object?> errorOf(WidgetTester tester, Future<void> navigation) async {
    Object? error;
    unawaited(navigation.catchError((Object e) => error = e));
    await tester.pumpAndSettle();
    return error;
  }

  testWidgets('A push whose guard throws leaves no guard in progress', (
    tester,
  ) async {
    await pumpRouterConfigApp(tester, router.config());
    doesThrow = true;

    final error = await errorOf(
      tester,
      router.push(const NamedRoute('AccountRoute')),
    );
    final stackAfterThrow = stackNames();
    expect(error, isStateError);
    expect(router.activeGuardObserver.guardInProgress, isFalse);

    // The push is over, so a later reevaluation has no guard of it to ask.
    doesThrow = false;
    await errorOf(tester, router.reevaluateGuards());
    expect(guardCalls, 1);
    expect(stackAfterThrow, ['HomeRoute']);
    expect(stackNames(), ['HomeRoute']);
  });

  testWidgets('A guard that throws during a reevaluation keeps the stack, and '
      'later reevaluations still run', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('OtherRoute')));
    await tester.pumpAndSettle();
    final stackBefore = stackNames();

    doesThrow = true;
    final error = await errorOf(tester, router.reevaluateGuards());

    expect(error, isStateError);
    expect(stackBefore, ['HomeRoute', 'AccountRoute', 'OtherRoute']);
    expect(stackNames(), ['HomeRoute', 'AccountRoute', 'OtherRoute']);
    expect(find.text('OtherRoute'), findsOneWidget);
    expect(router.activeGuardObserver.guardInProgress, isFalse);

    // The next reevaluation asks the guard again; it now rejects Account,
    // which closes with the page above it.
    doesThrow = false;
    isAllowed = false;
    expect(await errorOf(tester, router.reevaluateGuards()), isNull);

    expect(stackNames(), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  testWidgets('A replaceAll whose guard throws keeps the stack', (
    tester,
  ) async {
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('OtherRoute')));
    await tester.pumpAndSettle();

    doesThrow = true;
    final error = await errorOf(
      tester,
      router.replaceAll([const NamedRoute('AccountRoute')]),
    );

    expect(error, isStateError);
    expect(stackNames(), ['HomeRoute', 'OtherRoute']);
    expect(find.text('OtherRoute'), findsOneWidget);
    expect(router.activeGuardObserver.guardInProgress, isFalse);
  });

  testWidgets('A pushAll whose later guard throws keeps the stack, and the '
      'next one goes in', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    const otherAndAccount = [
      NamedRoute('OtherRoute'),
      NamedRoute('AccountRoute'),
    ];

    doesThrow = true;
    final error = await errorOf(tester, router.pushAll(otherAndAccount));

    expect(error, isStateError);
    expect(stackNames(), ['HomeRoute']);
    expect(router.activeGuardObserver.guardInProgress, isFalse);

    doesThrow = false;
    expect(await errorOf(tester, router.pushAll(otherAndAccount)), isNull);

    expect(stackNames(), ['HomeRoute', 'OtherRoute', 'AccountRoute']);
  });
}
