import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigate to a shell already open, which its guard rejects, leaves the
// stack, the url and the shell's children as they were, as a traversal the
// web's navigate event cancels and an unwind segue iOS and macOS don't
// perform leave every screen in place.
// Headless test: auto_route/test/guards/navigate_rejected_keeps_stack_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigate rejected keeps stack', () {
    late bool isOpen;
    late bool isLoginShown;

    Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));

    RootStackRouter buildRouter() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'FirstRoute',
          path: '/first',
          builder: (_, _) => page('FirstRoute'),
        ),
        NamedRouteDef(
          name: 'LoginRoute',
          path: '/login',
          builder: (_, data) => Scaffold(
            body: SafeArea(
              child: TextButton(
                onPressed: data.args! as VoidCallback,
                child: const Text('Cancel login'),
              ),
            ),
          ),
        ),
        NamedRouteDef.shell(
          name: 'ShellRoute',
          path: '/shell/:id',
          guards: [
            AutoRouteGuard.simple((resolver, _) {
              if (isLoginShown) {
                unawaited(
                  resolver.redirectUntil(
                    NamedRoute('LoginRoute', args: () => resolver.reject()),
                  ),
                );
              } else if (isOpen) {
                resolver.next();
              } else {
                resolver.reject();
              }
            }),
          ],
          children: [
            for (final (name, path) in [
              ('ChildARoute', 'a'),
              ('ChildBRoute', 'b'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, data) => Scaffold(
                  body: SafeArea(
                    child: Text(
                      '$name in shell '
                      '${data.inheritedPathParams.rawMap['id']}',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    // Opens [Home, Shell(id: 1, children: [ChildA]), First].
    Future<RootStackRouter> openShellUnderFirst(WidgetTester tester) async {
      isOpen = true;
      isLoginShown = false;
      final router = buildRouter();
      await pumpRouterAppWithConfig(tester, router);
      unawaited(
        router.push(
          const NamedRoute(
            'ShellRoute',
            params: {'id': 1},
            children: [NamedRoute('ChildARoute')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('FirstRoute')));
      await tester.pumpAndSettle();
      return router;
    }

    const shellTwo = NamedRoute(
      'ShellRoute',
      params: {'id': 2},
      children: [NamedRoute('ChildBRoute')],
    );

    // Steps: open the shell, push First, close the shell's guard, navigate to
    // Shell(id: 2, children: [ChildB]), then go back.
    // Should: First stays on screen and in the url, and back shows ChildA in
    // shell 1.
    testWidgets(
      'navigate to a shell already open that its guard now rejects leaves '
      'the stack as it was',
      (tester) async {
        final router = await openShellUnderFirst(tester);

        isOpen = false;
        unawaited(router.navigate(shellTwo));
        await tester.pumpAndSettle();

        expect(router.stack.map((e) => e.routeData.name), [
          'HomeRoute',
          'ShellRoute',
          'FirstRoute',
        ]);
        expectTopPage(router, 'FirstRoute');
        await expectBrowserUrl('/first');

        await systemBack(tester);

        expect(find.text('ChildARoute in shell 1'), findsOneWidget);
        await expectBrowserUrl('/shell/1/a');
      },
    );

    // Steps: open the shell, push First, navigate to Shell(id: 2) while its
    // guard redirects to a login page, tap 'Cancel login', then go back.
    // Should: First is on screen again, and back shows ChildA in shell 1.
    testWidgets(
      'canceling the login the guard of a shell already open shows leaves '
      'the stack as it was',
      (tester) async {
        final router = await openShellUnderFirst(tester);

        isLoginShown = true;
        unawaited(router.navigate(shellTwo));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel login'));
        await tester.pumpAndSettle();

        expectTopPage(router, 'FirstRoute');
        await expectBrowserUrl('/first');

        await systemBack(tester);

        expect(find.text('ChildARoute in shell 1'), findsOneWidget);
        await expectBrowserUrl('/shell/1/a');
      },
    );
  });
}
