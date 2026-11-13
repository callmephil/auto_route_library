import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page closes when the state its guard reads changes a second time while
// the guard still runs its check for the first change: the last change wins,
// as Flutter's Router works on the newest route information.
// Headless test: auto_route/test/reevaluatable_router/change_during_guard_check_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('change during guard check', () {
    // Steps: open Home, push Account, behind an async guard that reads the
    // session and then waits. The reevaluateListenable notifies while the
    // session is still valid; while the guard waits, the session ends and
    // the listenable notifies again. The guard's wait ends.
    // Was: Account stayed open, on the answer from before the second change.
    // Should: Account closes and Home shows.
    testWidgets('A page closes when its session ends while its guard runs a '
        'check', (tester) async {
      final isSessionValid = ValueNotifier(true);
      addTearDown(isSessionValid.dispose);
      final waits = <Completer<void>>[];
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'AccountRoute',
            path: '/account',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                final wasValid = isSessionValid.value;
                if (waits.isNotEmpty) await waits.removeAt(0).future;
                if (wasValid) {
                  resolver.next();
                } else {
                  resolver.reject();
                }
              }),
            ],
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('AccountRoute'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterConfigApp(
        tester,
        router.config(
          reevaluateListenable: session,
          deepLinkBuilder: (link) => link.initial ? DeepLink.defaultPath : link,
        ),
      );
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      final shownAtFirst = find.text('AccountRoute').evaluate().length;

      final slow = Completer<void>();
      waits.add(slow);
      session.value++;
      await tester.pump();
      isSessionValid.value = false;
      session.value++;
      await tester.pump();
      expect(
        (shownAtFirst, find.text('AccountRoute').evaluate().length),
        (1, 1),
      );
      slow.complete();
      await tester.pumpAndSettle();

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('AccountRoute'), findsNothing);
      expect(find.text('HomeRoute'), findsOneWidget);
    });
  });
}
