import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, a router.back() whose target a guard rejects keeps the
// history, so once the guard lets the user through, back() reaches the
// guarded page.
// Headless test: auto_route/test/back_rejected_by_guard_history_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back rejected by guard', () {
    // Steps: push Guarded over Home, then navigate to Home, which leaves
    // Home alone on the stack and three history entries. Close the guard and
    // tap 'Back', whose handler is the router's back method. Open the guard
    // and tap 'Back' again.
    // Was: the rejected back dropped Home's entry, so the second tap skipped
    // Guarded and stayed on Home.
    // Should: the rejected back changes nothing; the second tap opens
    // Guarded.
    // Native behavior: a refused navigation changes nothing, as a pop a
    // PopScope refuses leaves every route of Flutter's Navigator in place.
    // Off the web only: on the web, back() is the browser's own back step.
    testWidgets(
      'back() to a page whose guard rejects keeps the history',
      (tester) async {
        final isOpen = ValueNotifier(true);
        addTearDown(isOpen.dispose);
        final router = RootStackRouter.build(
          routes: [
            for (final (name, path) in [
              ('HomeRoute', '/'),
              ('GuardedRoute', '/guarded'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                guards: [
                  if (name == 'GuardedRoute')
                    AutoRouteGuard.simple(
                      (resolver, _) =>
                          isOpen.value ? resolver.next() : resolver.reject(),
                    ),
                ],
                builder: (context, _) => Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        Text(name),
                        TextButton(
                          onPressed: context.router.back,
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('GuardedRoute')));
        await tester.pumpAndSettle();
        unawaited(router.navigate(const NamedRoute('HomeRoute')));
        await tester.pumpAndSettle();

        isOpen.value = false;
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        final onHome = find.text('HomeRoute').evaluate().length;

        isOpen.value = true;
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect((onHome, find.text('GuardedRoute').evaluate().length), (1, 1));
      },
      skip: kIsWeb,
    );
  });
}
