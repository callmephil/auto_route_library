import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/pages.dart';

// A replaceAll that keeps the shell on top changes the shell's children only
// once every guard of the batch has let it in.
// Headless test: replace_all_shell_on_top_waits_for_guards_test.dart in the
// auto_route package's test/simple_router folder.
// Flutter's Router keeps building the current configuration while
// RouterDelegate.setNewRoutePath waits, and rebuilds once it completes; its
// Navigator then takes the new pages, with the nested Navigator built from a
// page's config, in one update.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaceAll keeps the shell on top behind a guard', () {
    // Steps: push ShellRoute showing ChildARoute, then call replaceAll with
    // HomeRoute, ShellRoute showing ChildBRoute, and GuardedRoute, whose
    // guard takes its time and then rejects it.
    // Happened: the shell showed ChildBRoute at /shell/b while the guard
    // decided, and stayed on it after the rejection.
    // Should: the shell shows ChildARoute at /shell/a throughout.
    testWidgets(
      'A guard that takes its time and rejects leaves the shell as it was',
      (tester) async {
        final guard = _HeldGuard();
        final router = _buildRouter(guard);
        await _openShellOnChildA(tester, router);
        await _replaceAllBehindGuard(tester, router);
        final shownWhileDeciding = find.text('Child A').evaluate().length;
        await expectBrowserUrl('/shell/a');

        guard.decision.complete(false);
        await tester.pumpAndSettle();
        expect(
          (shownWhileDeciding, find.text('Child A').evaluate().length),
          (1, 1),
        );
        expect(find.text('Child B'), findsNothing);
        expect(router.currentUrl, '/shell/a');
        await expectBrowserUrl('/shell/a');
      },
    );

    // Steps: push ShellRoute showing ChildARoute, call replaceAll with
    // HomeRoute, ShellRoute showing ChildBRoute, and GuardedRoute, whose
    // guard takes its time, let it in, then go back with system back.
    // Happened: the shell showed ChildBRoute at /shell/b while the guard
    // decided, and /guarded then went in as a new history entry.
    // Should: the shell keeps ChildARoute while the guard decides; /guarded
    // replaces the history entry, and back shows the shell on ChildBRoute.
    testWidgets(
      'The shell shows the new child once a guard lets the batch in',
      (tester) async {
        final guard = _HeldGuard();
        final router = _buildRouter(guard);
        await _openShellOnChildA(tester, router);
        await expectBrowserEntryAfter(0, () async {
          await _replaceAllBehindGuard(tester, router);
          expect(find.text('Child A'), findsOneWidget);
          await expectBrowserUrl('/shell/a');

          guard.decision.complete(true);
          await tester.pumpAndSettle();
        });
        expect(find.text('Guarded'), findsOneWidget);
        await expectBrowserUrl('/guarded');

        await systemBack(tester);
        expect(find.text('Child B'), findsOneWidget);
        expect(find.text('Child A'), findsNothing);
        expect(router.currentUrl, '/shell/b');
        await expectBrowserUrl('/shell/b');
      },
    );
  });
}

/// Lets its route in, or keeps it out, once the test decides.
class _HeldGuard extends AutoRouteGuard {
  final decision = Completer<bool>();

  @override
  Future<void> onNavigation(
    NavigationResolver resolver,
    StackRouter router,
  ) async {
    if (await decision.future) {
      resolver.next();
    } else {
      resolver.reject();
    }
  }
}

RootStackRouter _buildRouter(_HeldGuard guard) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const TextPage('Home'),
    ),
    NamedRouteDef(
      name: 'GuardedRoute',
      path: '/guarded',
      guards: [guard],
      builder: (_, _) => const TextPage('Guarded'),
    ),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell',
      builder: (_, _) => const Scaffold(body: SafeArea(child: AutoRouter())),
      children: [
        NamedRouteDef(
          name: 'ChildARoute',
          path: 'a',
          builder: (_, _) => const Text('Child A'),
        ),
        NamedRouteDef(
          name: 'ChildBRoute',
          path: 'b',
          builder: (_, _) => const Text('Child B'),
        ),
      ],
    ),
  ],
);

// Starts the app and pushes ShellRoute showing ChildARoute.
Future<void> _openShellOnChildA(
  WidgetTester tester,
  RootStackRouter router,
) async {
  await pumpRouterAppWithConfig(tester, router);
  unawaited(
    router.push(
      const NamedRoute('ShellRoute', children: [NamedRoute('ChildARoute')]),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Child A'), findsOneWidget);
}

// Calls replaceAll with HomeRoute, ShellRoute showing ChildBRoute, and
// GuardedRoute, whose guard holds it until the test decides.
Future<void> _replaceAllBehindGuard(
  WidgetTester tester,
  RootStackRouter router,
) async {
  unawaited(
    router.replaceAll(const [
      NamedRoute('HomeRoute'),
      NamedRoute('ShellRoute', children: [NamedRoute('ChildBRoute')]),
      NamedRoute('GuardedRoute'),
    ]),
  );
  await tester.pumpAndSettle();
}
