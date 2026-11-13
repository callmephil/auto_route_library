import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigation called right after a push, in the same handler, acts on the
// pushed page, as Flutter's Navigator changes its history at each call.
// Headless test: auto_route/test/navigations_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigations in one turn', () {
    RootStackRouter buildRouter() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (context, _) => Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const Text('HomeRoute'),
                  TextButton(
                    onPressed: () {
                      final router = context.router;
                      unawaited(router.push(const NamedRoute('LoadingRoute')));
                      unawaited(
                        router.replace(const NamedRoute('ResultRoute')),
                      );
                    },
                    child: const Text('Push then replace'),
                  ),
                  TextButton(
                    onPressed: () {
                      final router = context.router;
                      unawaited(router.push(const NamedRoute('LoadingRoute')));
                      unawaited(
                        router.replaceAll([const NamedRoute('ResultRoute')]),
                      );
                    },
                    child: const Text('Push then replaceAll'),
                  ),
                ],
              ),
            ),
          ),
        ),
        NamedRouteDef(
          name: 'LoadingRoute',
          path: '/loading',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('LoadingRoute'))),
        ),
        NamedRouteDef(
          name: 'ResultRoute',
          path: '/result',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('ResultRoute'))),
        ),
      ],
    );

    // Steps: open Home and tap 'Push then replace', whose handler calls
    // push(Loading) and replace(Result) with no await between them. Go back.
    // Was: the replace took Home off, so the stack was [Loading, Result] and
    // back showed Loading.
    // Should: Result takes the place of Loading, over Home, and back shows
    // Home.
    testWidgets('A replace right after a push replaces the pushed page', (
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
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(find.text('LoadingRoute'), findsNothing);
    });

    // Steps: open Home and tap 'Push then replaceAll', whose handler calls
    // push(Loading) and replaceAll([Result]) with no await between them.
    // Was: Loading was added after the stack was replaced, so the stack was
    // [Loading, Result] and back showed Loading.
    // Should: Result is the only page.
    testWidgets('A replaceAll right after a push leaves only its own pages', (
      tester,
    ) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());

      await tester.tap(find.text('Push then replaceAll'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['ResultRoute']);
      expect(find.text('ResultRoute'), findsOneWidget);
      expect(find.text('LoadingRoute'), findsNothing);
      await expectBrowserUrl('/result');
    });
  });
}
