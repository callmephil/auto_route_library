import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/pages.dart';

// The nested router of a shell replaceAll keeps below the top belongs to the
// page that keeps the shell, and to no other page of the shell's route.
// Headless test: replace_all_kept_shell_keeps_its_route_data_test.dart in the
// auto_route package's test/simple_router folder.
// Flutter's Navigator hands a route it shows, with the nested Navigator built
// inside it, only to the new page with the same key, and builds a new route
// for a page with a new key (Navigator._updatePages); a navigation a guard
// rejects never reaches it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaceAll keeps a shell below the top with its own route data', () {
    setUp(() => _isGuardOpen = true);

    // Steps: push GuardedRoute, ShellRoute 1 showing ChildARoute, and
    // FirstRoute. With GuardedRoute's guard closed, call replaceAll with
    // HomeRoute, GuardedRoute, ShellRoute 2 showing ChildBRoute, and
    // SecondRoute. Open the guard, push ShellRoute 3 showing ChildCRoute, go
    // back twice, then tap Open Child B in shell 1.
    // Happened: shell 1's nested router had the route data of the ShellRoute 3
    // page that was closed, so Child B showed shell 3's id.
    // Should: Child B shows shell 1's id, at /shell/1/b.
    testWidgets('A rejected replaceAll leaves the kept shell its own data', (
      tester,
    ) async {
      final router = _buildRouter();
      await pumpRouterAppWithConfig(tester, router);
      await _push(tester, router, const NamedRoute('GuardedRoute'));
      await _push(tester, router, _shell(1, 'ChildARoute'));
      await _push(tester, router, const NamedRoute('FirstRoute'));

      _isGuardOpen = false;
      unawaited(
        router.replaceAll([
          const NamedRoute('HomeRoute'),
          const NamedRoute('GuardedRoute'),
          _shell(2, 'ChildBRoute'),
          const NamedRoute('SecondRoute'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      _isGuardOpen = true;
      await _push(tester, router, _shell(3, 'ChildCRoute'));
      expect(find.text('Child C in shell 3'), findsOneWidget);

      await systemBack(tester);
      await systemBack(tester);
      expect(find.text('Child A in shell 1'), findsOneWidget);
      await tester.tap(find.text('Open Child B'));
      await tester.pumpAndSettle();
      expect(find.text('Child B in shell 1'), findsOneWidget);
      expect(router.currentUrl, '/shell/1/b');
      await expectBrowserUrl('/shell/1/b');
    });

    // Steps: push FirstRoute, ShellRoute 1 showing ChildARoute, and
    // SecondRoute, then call replaceAll with HomeRoute, ShellRoute 2 showing
    // ChildCRoute, FirstRoute, ShellRoute 3 showing ChildBRoute, and
    // SecondRoute, and go back.
    // Happened: ShellRoute 3 kept shell 1's screen, but the screen's nested
    // router took ShellRoute 2's route data, so Child B showed shell 2's id
    // at /shell/3/b.
    // Should: Child B shows shell 3's id.
    testWidgets(
      'An earlier page of the route in the batch leaves the kept shell alone',
      (tester) async {
        final router = _buildRouter();
        await pumpRouterAppWithConfig(tester, router);
        await _push(tester, router, const NamedRoute('FirstRoute'));
        await _push(tester, router, _shell(1, 'ChildARoute'));
        await _push(tester, router, const NamedRoute('SecondRoute'));

        unawaited(
          router.replaceAll([
            const NamedRoute('HomeRoute'),
            _shell(2, 'ChildCRoute'),
            const NamedRoute('FirstRoute'),
            _shell(3, 'ChildBRoute'),
            const NamedRoute('SecondRoute'),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Second'), findsOneWidget);

        await systemBack(tester);
        expect(find.text('Child B in shell 3'), findsOneWidget);
        expect(router.currentUrl, '/shell/3/b');
        await expectBrowserUrl('/shell/3/b');
      },
    );
  });
}

// Whether GuardedRoute's guard lets it in.
var _isGuardOpen = true;

// A child of the shell: shows the shell id it inherits, with a button that
// opens ChildBRoute in the same shell.
NamedRouteDef _child(String name, String path) => .new(
  name: 'Child${name}Route',
  path: path,
  builder: (context, data) => Column(
    children: [
      Text('Child $name in shell ${data.inheritedPathParams.getString('id')}'),
      TextButton(
        onPressed: () => context.router.push(const NamedRoute('ChildBRoute')),
        child: const Text('Open Child B'),
      ),
    ],
  ),
);

RootStackRouter _buildRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const TextPage('Home'),
    ),
    NamedRouteDef(
      name: 'FirstRoute',
      path: '/first',
      builder: (_, _) => const TextPage('First'),
    ),
    NamedRouteDef(
      name: 'SecondRoute',
      path: '/second',
      builder: (_, _) => const TextPage('Second'),
    ),
    NamedRouteDef(
      name: 'GuardedRoute',
      path: '/guarded',
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          if (_isGuardOpen) {
            resolver.next();
          } else {
            resolver.reject();
          }
        }),
      ],
      builder: (_, _) => const TextPage('Guarded'),
    ),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell/:id',
      builder: (_, _) => const Scaffold(body: SafeArea(child: AutoRouter())),
      children: [_child('A', 'a'), _child('B', 'b'), _child('C', 'c')],
    ),
  ],
);

NamedRoute<Object?> _shell(int id, String child) =>
    .new('ShellRoute', params: {'id': id}, children: [NamedRoute(child)]);

Future<void> _push(
  WidgetTester tester,
  RootStackRouter router,
  PageRouteInfo route,
) async {
  unawaited(router.push(route));
  await tester.pumpAndSettle();
}
