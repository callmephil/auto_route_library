import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard that rejects a route of a batch rejects the whole batch: pushAll
// leaves the stack, the screen and the url as they were, as Flutter's
// Navigator takes a new list of pages as one update and the web's navigate
// event cancels a navigation with the url and the current entry left as they
// were.
// Headless test: auto_route/test/guards/batch_rejected_keeps_stack_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('batch rejected keeps stack', () {
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
          name: 'SecondRoute',
          path: '/second',
          guards: [
            AutoRouteGuard.simple((resolver, _) {
              if (isLoginShown) {
                unawaited(
                  resolver.redirectUntil(
                    NamedRoute('LoginRoute', args: () => resolver.reject()),
                  ),
                );
              } else {
                resolver.reject();
              }
            }),
          ],
          builder: (_, _) => page('SecondRoute'),
        ),
        NamedRouteDef(
          name: 'ThirdRoute',
          path: '/third',
          builder: (_, _) => page('ThirdRoute'),
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
      ],
    );

    const firstAndSecond = [
      NamedRoute('FirstRoute'),
      NamedRoute('SecondRoute'),
    ];

    // Pushes Third and goes back: the page under Third is Home, not First.
    Future<void> expectHomeUnderThird(
      WidgetTester tester,
      RootStackRouter router,
    ) async {
      unawaited(router.push(const NamedRoute('ThirdRoute')));
      await tester.pumpAndSettle();
      await systemBack(tester);

      expect(router.stack.map((e) => e.routeData.name), ['HomeRoute']);
      expectTopPage(router, 'HomeRoute');
      expect(find.text('FirstRoute'), findsNothing);
      await expectBrowserUrl('/');
    }

    // Steps: open Home, pushAll([First, Second]) where Second's guard
    // rejects, then push Third and go back.
    // Should: Home stays on screen and in the url, and back from Third shows
    // Home.
    testWidgets(
      'pushAll rejected by a later guard leaves the stack as it was',
      (tester) async {
        isLoginShown = false;
        final router = buildRouter();
        await pumpRouterAppWithConfig(tester, router);

        unawaited(router.pushAll(firstAndSecond));
        await tester.pumpAndSettle();

        expect(router.stack.map((e) => e.routeData.name), ['HomeRoute']);
        expectTopPage(router, 'HomeRoute');
        await expectBrowserUrl('/');

        await expectHomeUnderThird(tester, router);
      },
    );

    // Steps: open Home, pushAll([First, Second]) while Second's guard
    // redirects to a login page, tap 'Cancel login', then push Third and go
    // back.
    // Should: Home is on screen again, and back from Third shows Home.
    testWidgets(
      'canceling the login a later guard of pushAll shows leaves '
      'the stack as it was',
      (tester) async {
        isLoginShown = true;
        final router = buildRouter();
        await pumpRouterAppWithConfig(tester, router);

        unawaited(router.pushAll(firstAndSecond));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel login'));
        await tester.pumpAndSettle();

        expect(router.stack.map((e) => e.routeData.name), ['HomeRoute']);
        expectTopPage(router, 'HomeRoute');
        await expectBrowserUrl('/');

        await expectHomeUnderThird(tester, router);
      },
    );
  });
}
