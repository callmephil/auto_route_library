import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A pop while a guard that was asked again has not answered closes the page
// on screen, as Flutter's Navigator.pop closes the route the user sees.
// Since Phil's decision 4 of 2026-11-16 the guard's page leaves the screen
// at once, so that is the page under it.
// Headless test:
// auto_route/test/reevaluatable_router/pop_while_held_back_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pop while held back', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home, the bills and the account. The session changes, so
    // the account's guard is asked again; it returns without an answer and
    // answers later, from a callback, and the account leaves the screen.
    // Before it answers, tap 'Close' on the bills, which calls pop. Then the
    // guard lets the account back.
    // Was: the pop left no page on the stack and an empty screen.
    // Should: the bills close and Home shows; the account comes back over
    // Home once its guard has answered.
    testWidgets('The page on screen closes and the page under it shows', (
      tester,
    ) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final answers = <VoidCallback>[];
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'AccountRoute',
            path: '/account',
            guards: [
              AutoRouteGuard.simple(
                (resolver, _) => session.value == 0
                    ? resolver.next()
                    : answers.add(resolver.next),
              ),
            ],
            builder: (_, _) => page('AccountRoute'),
          ),
          NamedRouteDef(
            name: 'BillsRoute',
            path: '/bills',
            builder: (context, _) => page('BillsRoute', [
              TextButton(
                onPressed: () => context.router.pop(),
                child: const Text('Close'),
              ),
            ]),
          ),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      for (final name in ['BillsRoute', 'AccountRoute']) {
        unawaited(router.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      session.value++;
      await tester.pumpAndSettle();
      final shownWhileAsked = find.text('AccountRoute').evaluate().length;
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expectTopPage(router, 'HomeRoute');
      for (final answer in answers) {
        answer();
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(answers, hasLength(1));
      expect(shownWhileAsked, 0);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
      ]);
      expect(find.text('AccountRoute'), findsOneWidget);
      expect(find.text('BillsRoute'), findsNothing);
    });
  });
}
