import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page a batch takes off answers its caller only once the batch is in: a
// batch a later guard rejects puts the page back with its caller still
// waiting, as Flutter's Navigator completes a route's future only when it
// applies a list of pages without that route, and the web's navigate event
// cancels a navigation without disposing the current entry.
// Headless test: auto_route/test/guards/batch_rejected_keeps_caller_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('batch rejected keeps caller', () {
    late bool isLoginShown;

    Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));

    RootStackRouter buildRouter() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        // A page that keeps no history, with a button that closes it with a
        // result.
        NamedRouteDef(
          name: 'NoticeRoute',
          path: '/notice',
          keepHistory: false,
          builder: (context, _) => Scaffold(
            body: SafeArea(
              child: TextButton(
                onPressed: () => unawaited(context.router.maybePop(7)),
                child: const Text('Answer 7'),
              ),
            ),
          ),
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

    // Opens Notice with push<int>, then runs pushAll([First, Second]), which
    // Second's guard rejects at once or once the login it shows is canceled.
    // Notice is back on screen and in the url, its caller still waits, and
    // tapping 'Answer 7' gives the caller 7.
    Future<void> expectCallerWaitsThroughRejectedBatch(
      WidgetTester tester,
    ) async {
      final router = buildRouter();
      await pumpRouterAppWithConfig(tester, router);
      var result = 'waiting';
      unawaited(
        router
            .push<int>(const NamedRoute('NoticeRoute'))
            .then((value) => result = 'got ${value ?? 'null'}'),
      );
      await tester.pumpAndSettle();

      unawaited(
        router.pushAll(const [
          NamedRoute('FirstRoute'),
          NamedRoute('SecondRoute'),
        ]),
      );
      await tester.pumpAndSettle();
      if (isLoginShown) {
        await tester.tap(find.text('Cancel login'));
        await tester.pumpAndSettle();
      }

      expect(router.stack.map((e) => e.routeData.name), [
        'HomeRoute',
        'NoticeRoute',
      ]);
      expect(find.text('Answer 7'), findsOneWidget);
      await expectBrowserUrl('/notice');
      expect(result, 'waiting');

      await tester.tap(find.text('Answer 7'));
      await tester.pumpAndSettle();

      expectTopPage(router, 'HomeRoute');
      expect(result, 'got 7');
    }

    // Steps: open Home, push Notice and wait for its result, push First and
    // Second in one batch, which Second's guard rejects, then tap 'Answer 7'.
    // Was: the push of Notice finished with null as the batch began, so the
    // 7 went to no one.
    testWidgets(
      'A page that keeps no history keeps its caller waiting when a later '
      'guard rejects the batch over it',
      (tester) async {
        isLoginShown = false;
        await expectCallerWaitsThroughRejectedBatch(tester);
      },
    );

    // Steps: as above, while Second's guard shows a login page; tap 'Cancel
    // login', then 'Answer 7'.
    testWidgets(
      'A page that keeps no history keeps its caller waiting when the login '
      'a later guard shows is canceled',
      (tester) async {
        isLoginShown = true;
        await expectCallerWaitsThroughRejectedBatch(tester);
      },
    );
  });
}
