import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigation whose guards answer in their own call is on the stack as its
// call returns, so a call made right after it in the same handler acts on
// its pages, as Flutter's Navigator changes its history at each call.
// Headless tests: auto_route/test/guards/guard_answers_at_once_test.dart and
// auto_route/test/navigations_after_batch_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('guard answers at once', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Every route has a guard that lets everyone through in its own call,
    // as a signed-in check does for a signed-in user.
    RootStackRouter buildRouter() => .build(
      guards: [AutoRouteGuard.simple((resolver, _) => resolver.next())],
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (context, _) => page('HomeRoute', [
            TextButton(
              onPressed: () {
                final router = context.router;
                unawaited(router.push(const NamedRoute('LoadingRoute')));
                unawaited(router.replace(const NamedRoute('ResultRoute')));
              },
              child: const Text('Push then replace'),
            ),
            TextButton(
              onPressed: () {
                final router = context.router;
                unawaited(
                  router.pushAll(const [
                    NamedRoute('LoadingRoute'),
                    NamedRoute('ResultRoute'),
                  ]),
                );
                unawaited(router.push(const NamedRoute('DetailsRoute')));
              },
              child: const Text('PushAll then push'),
            ),
          ]),
        ),
        for (final (name, path) in [
          ('LoadingRoute', '/loading'),
          ('ResultRoute', '/result'),
          ('DetailsRoute', '/details'),
        ])
          NamedRouteDef(name: name, path: path, builder: (_, _) => page(name)),
      ],
    );

    // Steps: every route has a guard that lets a signed-in user through in
    // its own call. Open Home and tap 'Push then replace', whose handler
    // calls push(Loading) and replace(Result) with no await between them. Go
    // back.
    // Was: the replace took Home off, so the stack was [Loading, Result] and
    // back showed Loading.
    // Should: Result takes the place of Loading, over Home, and back shows
    // Home.
    testWidgets('A replace after a guarded push replaces that page', (
      tester,
    ) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Push then replace'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'ResultRoute',
      ]);
      expect(find.text('ResultRoute'), findsOneWidget);
      await expectBrowserUrl('/result');

      await systemBack(tester);

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('LoadingRoute'), findsNothing);
    });

    // Steps: open Home and tap 'PushAll then push'. Its handler opens Loading
    // and Result with one pushAll call and then Details with a push call,
    // with no await between the two. Go back.
    // Was: Details went in first and ended under the other two, so Result
    // was on screen.
    // Should: Details is on screen, over Result, and back shows Result.
    testWidgets('A push after pushAll lands on top', (tester) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('PushAll then push'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'LoadingRoute',
        'ResultRoute',
        'DetailsRoute',
      ]);
      expect(find.text('DetailsRoute'), findsOneWidget);
      await expectBrowserUrl('/details');

      await systemBack(tester);

      expect(router.topRoute.name, 'ResultRoute');
      expect(find.text('ResultRoute'), findsOneWidget);
    });
  });
}
