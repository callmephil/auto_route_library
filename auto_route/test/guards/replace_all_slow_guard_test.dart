import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../tap_count_page.dart';

// While a guard of replaceAll decided, the stack was empty: the app showed a
// blank screen as soon as anything rebuilt it, and the pages a rejected
// replaceAll put back had lost their State. Found by the audit of
// auto_route/lib at dev 56b73492 (finding C3).
// Steps: open Home, push<int> Form and count a tap on it.
// replaceAll([Guarded]), whose async guard waits. The widget above
// MaterialApp.router rebuilds meanwhile, as on a theme, locale or sign-in
// change. The guard rejects, or accepts.
// Was: router.stack was [] and router.current the root while the guard
// decided. The rebuild found no page, so the Navigator left the tree with
// every route; after the rejection Form came back with its count at 0, and
// the code that opened it had been told it closed.
// Should: the pages stay on the stack and on screen until every guard has
// let the new routes through, then the stack is swapped in one step. A
// rejection changes nothing. Flutter's Router keeps building the current
// pages while its delegate waits; on the web a navigation that is not
// committed leaves the current document on screen; on iOS setViewControllers
// swaps the stack in one step, with nothing shown in between.
void main() {
  late RootStackRouter router;
  late Completer<bool> decision;

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

  // Not in setUp: the completer the guard waits on must be made inside the
  // test, under its fake clock.
  void buildRouter() {
    decision = Completer<bool>();
    router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        NamedRouteDef(
          name: 'FormRoute',
          path: '/form',
          builder: (_, _) => const TapCountPage('Form'),
        ),
        plainRoute('OpenRoute', '/open'),
        plainRoute(
          'GuardedRoute',
          '/guarded',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              if (await decision.future) {
                resolver.next();
              } else {
                resolver.reject();
              }
            }),
          ],
        ),
      ],
    );
  }

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  // Shows the router under a widget that can rebuild the whole app, as an
  // app that watches its theme above MaterialApp.router does. Returns the
  // function that rebuilds it.
  Future<VoidCallback> pumpRebuildableApp(WidgetTester tester) async {
    buildRouter();
    final config = router.config();
    addTearDown(router.dispose);
    var brightness = Brightness.light;
    late StateSetter setAppState;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setAppState = setState;
          return MaterialApp.router(
            theme: ThemeData(brightness: brightness),
            routerConfig: config,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    return () =>
        setAppState(() => brightness = brightness == .light ? .dark : .light);
  }

  // Opens Form with one tap counted, then starts [replaceAll] and rebuilds
  // the app while its guard waits. Returns what the code that opened Form got
  // so far.
  Future<String Function()> openFormThenReplaceAll(
    WidgetTester tester,
    List<PageRouteInfo> routes,
  ) async {
    final rebuildApp = await pumpRebuildableApp(tester);
    var formResult = 'waiting';
    unawaited(
      router
          .push<int>(const NamedRoute('FormRoute'))
          .then((value) => formResult = 'got ${value ?? 'null'}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form 0'));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll(routes));
    await tester.pump();
    rebuildApp();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return () => formResult;
  }

  testWidgets('The pages stay on the stack and on screen while a guard of '
      'replaceAll decides, and keep their State when it rejects', (
    tester,
  ) async {
    final formResult = await openFormThenReplaceAll(tester, [
      const NamedRoute('GuardedRoute'),
    ]);

    final stackWhileDeciding = stackNames();
    final formShownWhileDeciding = find.text('Form 1').evaluate().length;
    expect(router.current.name, 'FormRoute');

    decision.complete(false);
    await tester.pumpAndSettle();

    expect(router.activeGuardObserver.guardInProgress, isFalse);
    expect(stackWhileDeciding, ['HomeRoute', 'FormRoute']);
    expect(stackNames(), ['HomeRoute', 'FormRoute']);
    expect(
      (formShownWhileDeciding, find.text('Form 1').evaluate().length),
      (1, 1),
    );
    expect(formResult(), 'waiting');
  });

  testWidgets('The pages are replaced in one step once the guard of '
      'replaceAll lets its route through', (tester) async {
    final formResult = await openFormThenReplaceAll(tester, [
      const NamedRoute('GuardedRoute'),
    ]);

    expect(stackNames(), ['HomeRoute', 'FormRoute']);
    expect(find.text('Form 1'), findsOneWidget);

    decision.complete(true);
    await tester.pumpAndSettle();

    expect(stackNames(), ['GuardedRoute']);
    expect(find.text('GuardedRoute'), findsOneWidget);
    expect(formResult(), 'got null');
  });

  // The guard of a later route decides: the route before it, which no guard
  // keeps out, doesn't go on alone meanwhile.
  testWidgets('No page of replaceAll goes on while the guard of a later one '
      'decides', (tester) async {
    final formResult = await openFormThenReplaceAll(tester, [
      const NamedRoute('OpenRoute'),
      const NamedRoute('GuardedRoute'),
    ]);

    final stackWhileDeciding = stackNames();
    final formShownWhileDeciding = find.text('Form 1').evaluate().length;
    expect(find.text('OpenRoute'), findsNothing);

    decision.complete(false);
    await tester.pumpAndSettle();

    expect(router.activeGuardObserver.guardInProgress, isFalse);
    expect(stackWhileDeciding, ['HomeRoute', 'FormRoute']);
    expect(stackNames(), ['HomeRoute', 'FormRoute']);
    expect(
      (formShownWhileDeciding, find.text('Form 1').evaluate().length),
      (1, 1),
    );
    expect(formResult(), 'waiting');
  });
}
