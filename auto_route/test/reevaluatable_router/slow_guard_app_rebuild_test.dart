import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../tap_count_page.dart';

// A page whose guard lets it stay closed when the app rebuilt while the guard
// was asked again, and with one guard for every route the whole app went
// blank meanwhile. Found by the audit of auto_route/lib at dev 56b73492, as
// finding C1.
// Setup: the app's session is a Listenable. It is the router's
// reevaluateListenable, and the widget above MaterialApp.router listens to it
// too, as an app that shows the signed-in user's theme or locale does. The
// guard awaits a check that takes 100 ms and then calls next(), as the README
// suggests for sign-in state.
// Steps: open Home, push Account and count a tap on it. Then the session
// notifies, as after a token refresh, so the guards are asked again and the
// app rebuilds, while the guard's check runs.
// Was: the stack was [Home], and Account had closed. A reevaluation took
// every page off the stack and put each back as its guard answered. The
// build in between handed the Navigator the pages put back so far, the
// Navigator removed Account's route, and the reevaluation took Account for a
// page the user had popped. With the guard in RootStackRouter.guards no page
// was left, so the Navigator itself left the tree.
// Should: the page stays on the stack and on screen, with its State, while
// its guard's check runs, and only the guard's answer closes it. Flutter's
// Router keeps building the current pages while its delegate waits on a
// future, and a Navigator keeps a route until its page leaves `pages`. On iOS
// and Android a sign-in check in flight leaves the view controller or the
// activity on screen. On the web a navigate handler that has not answered
// leaves the document as it is.
void main() {
  AutoRouteGuard slowGuard() => .simple((resolver, _) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    resolver.next();
  });

  NamedRouteDef countingRoute(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: '${name}Route',
    path: path,
    guards: guards,
    builder: (_, _) => TapCountPage(name),
  );

  // Shows [router] under a widget that rebuilds the app when [session]
  // notifies, which also asks the guards again.
  Future<void> pumpSessionApp(
    WidgetTester tester,
    RootStackRouter router,
    ValueNotifier<int> session,
  ) async {
    final config = router.config(reevaluateListenable: session);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: session,
        builder: (_, _) => MaterialApp.router(
          title: 'Session ${session.value}',
          routerConfig: config,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets(
    'A page its async guard keeps stays, with its State, when the app '
    'rebuilds while the guard decides',
    (tester) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          countingRoute('Home', '/'),
          countingRoute('Account', '/account', guards: [slowGuard()]),
        ],
      );
      await pumpSessionApp(tester, router, session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account 0'));
      await tester.pumpAndSettle();
      expect(find.text('Account 1'), findsOneWidget);

      session.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final stackWhileDeciding = stackNames(router);
      final shownWhileDeciding = find.text('Account 1').evaluate().length;
      await tester.pumpAndSettle();

      expect(stackWhileDeciding, ['HomeRoute', 'AccountRoute']);
      expect(shownWhileDeciding, 1, reason: 'on screen while deciding');
      expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
      expect(find.text('Account 1'), findsOneWidget);
    },
  );

  // The same with one guard for every route, in RootStackRouter.guards, as an
  // app that checks the session in one place has.
  testWidgets(
    'The first page keeps its State when the app rebuilds while a guard of '
    'the root router decides',
    (tester) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        guards: [slowGuard()],
        routes: [countingRoute('Home', '/')],
      );
      await pumpSessionApp(tester, router, session);
      await tester.tap(find.text('Home 0'));
      await tester.pumpAndSettle();
      expect(find.text('Home 1'), findsOneWidget);

      session.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final shownWhileDeciding = find.text('Home 1').evaluate().length;
      await tester.pumpAndSettle();

      expect(shownWhileDeciding, 1, reason: 'on screen while deciding');
      expect(stackNames(router), ['HomeRoute']);
      expect(find.text('Home 1'), findsOneWidget);
    },
  );

  // The page above a page whose guard is asked again is not asked yet: it
  // stays too, and closes only when the guard below it rejects.
  testWidgets(
    'The pages above a page whose async guard decides stay until it answers',
    (tester) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final router = RootStackRouter.build(
        routes: [
          countingRoute('Home', '/'),
          countingRoute(
            'Account',
            '/account',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                if (isSignedIn.value) {
                  resolver.next();
                } else {
                  resolver.reject();
                }
              }),
            ],
          ),
          countingRoute('Details', '/details'),
        ],
      );
      await pumpSessionApp(tester, router, session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details 0'));
      await tester.pumpAndSettle();

      session.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final stackWhileDeciding = stackNames(router);
      await tester.pumpAndSettle();

      expect(stackWhileDeciding, ['HomeRoute', 'AccountRoute', 'DetailsRoute']);
      expect(find.text('Details 1'), findsOneWidget);

      isSignedIn.value = false;
      session.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(stackNames(router), ['HomeRoute', 'AccountRoute', 'DetailsRoute']);
      expect(find.text('Details 1'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(stackNames(router), ['HomeRoute']);
      expect(find.text('Home 0'), findsOneWidget);
    },
  );
}
