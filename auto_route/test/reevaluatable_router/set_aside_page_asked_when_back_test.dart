import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page came back for a signed-out user when the session ended while the
// page was set aside for the page of a guard of replaceAll. A lead of the
// audit of auto_route/lib, new with its replaceAll that sets the open pages
// aside for a guard's page.
// Setup: Home is open to everyone. Account and Bills sit behind a guard that
// reads the session, which is the router's reevaluateListenable. Vault sits
// behind a guard that sends a locked user to a pin page with redirectUntil.
// Steps: signed in on Home, Account and Bills, the app replaces the pages
// with Vault, and the pin page takes their place. The session ends. The user
// cancels the pin page, so the guard rejects and the pages come back.
// Was: Home, Account and Bills for the signed-out user, until the next
// change of the session. The reevaluation the sign-out started asked about
// the pages on the stack, which Account and Bills had left. An answer of
// Account's guard that came while its page was off was dropped.
// Should: the pages are asked as they come back, and Account closes with
// Bills. UIKit calls viewWillAppear and Android calls onResume on a screen
// that comes back to the top, which is where an app checks the session
// again.
void main() {
  late ValueNotifier<bool> isSignedIn;
  late List<NavigationResolver> locking;
  late List<String> asked;
  // The requests a session guard waits for, one per call, in order.
  late List<Completer<void>> requests;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    locking = [];
    asked = [];
    requests = [];
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

  // Reads the session once its request, if it waits for one, is back.
  AutoRouteGuard sessionGuard(String name) => .simple((resolver, _) async {
    asked.add(name);
    if (requests.isNotEmpty) await requests.removeAt(0).future;
    isSignedIn.value ? resolver.next() : resolver.reject();
  });

  // Sends the user to the page of [pinRoute]. A change of the session asks
  // it again while that page is open; it goes on waiting.
  AutoRouteGuard pinGuard(String pinRoute) => .simple((resolver, _) {
    if (resolver.isReevaluating) return;
    locking.add(resolver);
    unawaited(resolver.redirectUntil(NamedRoute(pinRoute)));
  });

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home, signed in, with Account and Bills over it unless
  // [isHomeAlone].
  Future<RootStackRouter> openBills(
    WidgetTester tester, {
    bool isHomeAlone = false,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('AccountRoute', '/account', guard: sessionGuard('Account')),
        page('BillsRoute', '/bills', guard: sessionGuard('Bills')),
        page('VaultRoute', '/vault', guard: pinGuard('PinRoute')),
        page('PinRoute', '/pin'),
        page(
          'ShellRoute',
          '/shell',
          children: [
            page('ListRoute', ''),
            page('DetailRoute', 'detail', guard: sessionGuard('Detail')),
            page('SafeRoute', 'safe', guard: pinGuard('CodeRoute')),
            page('CodeRoute', 'code'),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    if (isHomeAlone) return router;
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('BillsRoute')));
    await tester.pumpAndSettle();
    asked.clear();
    return router;
  }

  // Calls replaceAll([VaultRoute()]), which waits behind the pin page.
  Future<List<NavigationFailure>> lock(
    WidgetTester tester,
    StackRouter router,
  ) async {
    final failures = <NavigationFailure>[];
    unawaited(
      router.replaceAll([
        const NamedRoute('VaultRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    expect(stackNames(router), ['PinRoute']);
    return failures;
  }

  testWidgets('The pages a guard of replaceAll set aside are asked as they '
      'come back when the session ended meanwhile', (tester) async {
    final router = await openBills(tester);
    final failures = await lock(tester, router);

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    final askedWhileAside = List.of(asked);
    locking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(askedWhileAside, isEmpty);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(asked, ['Account']);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  // The session ends first, and Account's guard still waits for its request
  // as the pin page takes the place of the pages: its answer comes while
  // its page is off the stack, and Bills is not asked in that round.
  testWidgets('The pages a guard of replaceAll set aside while a slow guard '
      'was asked again are asked as they come back', (tester) async {
    final router = await openBills(tester);
    final request = Completer<void>();
    requests.add(request);

    isSignedIn.value = false;
    await tester.pump();
    await tester.pump();
    final askedAtWait = List.of(asked);
    await lock(tester, router);
    request.complete();
    await tester.pumpAndSettle();
    final whileAside = stackNames(router);
    locking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(askedAtWait, ['Account']);
    expect(whileAside, ['PinRoute']);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  testWidgets('The pages of a nested router that a guard of replaceAll set '
      'aside are asked as they come back', (tester) async {
    final router = await openBills(tester, isHomeAlone: true);
    unawaited(router.push(const NamedRoute('ShellRoute')));
    await tester.pumpAndSettle();
    final shell = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(shell?.push(const NamedRoute('DetailRoute')));
    await tester.pumpAndSettle();
    asked.clear();
    final failures = <NavigationFailure>[];
    unawaited(
      shell?.replaceAll([
        const NamedRoute('SafeRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    final whileAside = shell == null ? null : stackNames(shell);

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    locking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(whileAside, ['CodeRoute']);
    expect(stackNames(router), ['HomeRoute', 'ShellRoute']);
    expect(shell == null ? null : stackNames(shell), ['ListRoute']);
    expect(find.text('ListRoute'), findsOneWidget);
    expect(asked, ['Detail']);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  // These two pass before the fix too.
  testWidgets('The pages a guard of replaceAll set aside are not asked as '
      'they come back when nothing changed meanwhile', (tester) async {
    final router = await openBills(tester);
    await lock(tester, router);

    locking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'AccountRoute', 'BillsRoute']);
    expect(asked, isEmpty);
  });

  testWidgets('The pages a guard of replaceAll set aside stay gone when the '
      'guard lets the new page in after the session ended', (tester) async {
    final router = await openBills(tester);
    await lock(tester, router);

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    locking.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['VaultRoute']);
    expect(asked, isEmpty);
  });
}
