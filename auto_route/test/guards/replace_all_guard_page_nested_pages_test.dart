import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The pages in the nested router of a page were gone when that page came
// back after the guard of a replaceAll rejected. A lead of the audit of
// auto_route/lib; on dev too.
// Setup: Vault sits behind a guard that sends a locked user to a pin page
// with redirectUntil. Shell is a page with a nested router, with List as
// its first page, Detail, and Extra behind a guard that reads the session.
// Steps: open Home and Shell, and push Detail in Shell. The app replaces the
// pages with Vault, and the pin page takes their place. The guard rejects,
// as a cancel button does, so Home and Shell are back.
// Was: Shell showed List. Its nested router left with its screen as the
// pin page went on, and the router Shell got as it came back opened only
// Shell's first page.
// Should: Shell shows Detail over List again, in a screen built anew. A
// replaceAll that a guard rejects changes nothing: Flutter's Navigator shows
// the pages it is given, and a page given to it again with the pages it
// names shows them, as a UINavigationController that is put back with
// setViewControllers shows the stack it holds.
// The code that opened Detail was told it closed, with null, as its screen
// left; that screen is gone, and the Detail that is back is a new one.
void main() {
  late ValueNotifier<bool> isSignedIn;
  late List<NavigationResolver> locking;
  late List<String> asked;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    locking = [];
    asked = [];
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

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  List<String>? shellNames(StackRouter router) =>
      switch (router.innerRouterOf<StackRouter>('ShellRoute')) {
        final shell? => stackNames(shell),
        null => null,
      };

  // Opens Home and Shell, with Detail over List in Shell and Extra over
  // that when [hasExtra], then calls replaceAll([VaultRoute()]), which waits
  // behind the pin page. What it reports goes to [failures].
  Future<RootStackRouter> lock(
    WidgetTester tester, {
    required List<NavigationFailure> failures,
    bool hasExtra = false,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'ShellRoute',
          '/shell',
          children: [
            page('ListRoute', ''),
            page('DetailRoute', 'detail'),
            page(
              'ExtraRoute',
              'extra',
              guard: AutoRouteGuard.simple((resolver, _) {
                asked.add('Extra');
                isSignedIn.value ? resolver.next() : resolver.reject();
              }),
            ),
          ],
        ),
        page(
          'VaultRoute',
          '/vault',
          // A change of the session asks it again while the pin page is
          // open; it goes on waiting.
          guard: AutoRouteGuard.simple((resolver, _) {
            if (resolver.isReevaluating) return;
            locking.add(resolver);
            unawaited(resolver.redirectUntil(const NamedRoute('PinRoute')));
          }),
        ),
        page('PinRoute', '/pin'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    unawaited(router.push(const NamedRoute('ShellRoute')));
    await tester.pumpAndSettle();
    final shell = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(shell?.push(const NamedRoute('DetailRoute')));
    await tester.pumpAndSettle();
    if (hasExtra) {
      unawaited(shell?.push(const NamedRoute('ExtraRoute')));
      await tester.pumpAndSettle();
    }
    asked.clear();
    unawaited(
      router.replaceAll([
        const NamedRoute('VaultRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    expect(stackNames(router), ['PinRoute']);
    return router;
  }

  for (final hasExtra in [false, true]) {
    final pages = hasExtra ? 'three pages' : 'two pages';
    testWidgets('The $pages in the nested router of a page a guard of '
        'replaceAll set aside are back when the guard rejects', (tester) async {
      final failures = <NavigationFailure>[];
      final router = await lock(tester, failures: failures, hasExtra: hasExtra);

      locking.singleOrNull?.reject();
      await tester.pumpAndSettle();
      final top = hasExtra ? 'ExtraRoute' : 'DetailRoute';

      expect(stackNames(router), ['HomeRoute', 'ShellRoute']);
      expect(shellNames(router), [
        'ListRoute',
        'DetailRoute',
        if (hasExtra) 'ExtraRoute',
      ]);
      expect(find.text(top), findsOneWidget);
      // Nothing changed meanwhile, so no guard is asked for what is back.
      expect(asked, isEmpty);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      router.innerRouterOf<StackRouter>('ShellRoute')?.pop();
      await tester.pumpAndSettle();
      expect(find.text(hasExtra ? 'DetailRoute' : 'ListRoute'), findsOneWidget);
    });
  }

  // The session ends while the pages are set aside: a page of the nested
  // router whose guard now rejects is not opened again, and the pages under
  // it are.
  testWidgets('A guarded page in the nested router of a page a guard of '
      'replaceAll set aside is asked as it comes back after a sign-out', (
    tester,
  ) async {
    final failures = <NavigationFailure>[];
    final router = await lock(tester, failures: failures, hasExtra: true);

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    locking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'ShellRoute']);
    expect(shellNames(router), ['ListRoute', 'DetailRoute']);
    expect(find.text('DetailRoute'), findsOneWidget);
    expect(asked, ['Extra']);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });

  // Passes before the fix too.
  testWidgets('The pages in the nested router of a page a guard of '
      'replaceAll set aside stay gone when the guard lets the new page in', (
    tester,
  ) async {
    final failures = <NavigationFailure>[];
    final router = await lock(tester, failures: failures);

    locking.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['VaultRoute']);
    expect(find.text('VaultRoute'), findsOneWidget);
    expect(shellNames(router), isNull);
    expect(failures, isEmpty);
  });
}
