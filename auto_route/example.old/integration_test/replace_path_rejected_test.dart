import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A replacePath() rejected by the new route's guard leaves the stack as it
// was, as a replace navigation the web's navigate event cancels leaves the url
// and the current entry, and Flutter's Navigator.pushReplacement takes the old
// route off only in the step that pushes the new one.
// Headless test: auto_route/test/guards/replace_path_rejected_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replacePath rejected', () {
    Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));

    NamedRouteDef plainRoute(String name, String path) =>
        .new(name: name, path: path, builder: (_, _) => page(name));

    RootStackRouter buildRouter({required bool isLoginShown}) => .build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute('FirstRoute', '/first'),
        plainRoute('ThirdRoute', '/third'),
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
      ],
    );

    Future<RootStackRouter> openFirst(
      WidgetTester tester, {
      required bool isLoginShown,
    }) async {
      final router = buildRouter(isLoginShown: isLoginShown);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('FirstRoute')));
      await tester.pumpAndSettle();
      return router;
    }

    // Steps: push First, replacePath('/second'), whose guard rejects it, push
    // Third, then go back.
    // Should: First stays on the stack, on screen and in the url, and back
    // from Third shows First again.
    testWidgets(
      'A replacePath rejected by a guard keeps the page it would replace',
      (tester) async {
        final router = await openFirst(tester, isLoginShown: false);

        unawaited(router.replacePath('/second'));
        await tester.pumpAndSettle();

        expect(router.stack.map((e) => e.routeData.name), [
          'HomeRoute',
          'FirstRoute',
        ]);
        expectTopPage(router, 'FirstRoute');
        await expectBrowserUrl('/first');

        unawaited(router.push(const NamedRoute('ThirdRoute')));
        await tester.pumpAndSettle();
        await systemBack(tester);

        expectTopPage(router, 'FirstRoute');
        await expectBrowserUrl('/first');
      },
    );

    // Steps: push First, replacePath('/second') while its guard redirects to
    // a login page, then tap 'Cancel login'.
    // Should: the login page opens over First, and canceling it shows First
    // again, in the url too.
    testWidgets(
      'Canceling the login a replacePath redirects to shows the page it would '
      'replace',
      (tester) async {
        final router = await openFirst(tester, isLoginShown: true);

        unawaited(router.replacePath('/second'));
        await tester.pumpAndSettle();
        expect(router.stack.map((e) => e.routeData.name), [
          'HomeRoute',
          'FirstRoute',
          'LoginRoute',
        ]);

        await tester.tap(find.text('Cancel login'));
        await tester.pumpAndSettle();

        expect(router.stack.map((e) => e.routeData.name), [
          'HomeRoute',
          'FirstRoute',
        ]);
        expectTopPage(router, 'FirstRoute');
        await expectBrowserUrl('/first');
      },
    );
  });
}
