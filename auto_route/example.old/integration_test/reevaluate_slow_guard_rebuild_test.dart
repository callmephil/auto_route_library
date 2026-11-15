import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page stays on screen, with its State, when the app rebuilds while the
// guard that is asked again still runs its check, as a sign-in check in
// flight leaves the screen up on iOS and Android.
// Headless test: auto_route/test/reevaluatable_router/slow_guard_app_rebuild_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('reevaluate slow guard rebuild', () {
    // Steps: the session is the router's reevaluateListenable, and the widget
    // above MaterialApp.router listens to it too. Open Home, push Account,
    // whose guard awaits a check, and tap it once. The session notifies: the
    // app rebuilds while the guard's check runs. Then the check ends and the
    // guard calls next().
    // Was: Account closed, although its guard let it stay.
    // Should: Account stays on screen with its count, during the check and
    // after it.
    testWidgets('A page its async guard keeps stays when the app rebuilds '
        'while the guard decides', (tester) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final checks = <Completer<void>>[];
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
                if (checks.isNotEmpty) await checks.removeAt(0).future;
                resolver.next();
              }),
            ],
            builder: (_, _) => const _TapCountPage(),
          ),
        ],
      );
      final config = router.config(
        reevaluateListenable: session,
        deepLinkBuilder: (link) => link.initial ? DeepLink.defaultPath : link,
      );
      addTearDown(router.dispose);
      bringAppToForeground(tester);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: session,
          builder: (_, _) => MaterialApp.router(
            title: 'Session ${session.value}',
            routerConfig: config,
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account 0'));
      await tester.pumpAndSettle();
      // Account on screen with its count, and the pages on the stack.
      (int, int) shown() =>
          (find.text('Account 1').evaluate().length, router.stack.length);
      expect(find.text('Account 1'), findsOneWidget);

      final running = Completer<void>();
      checks.add(running);
      session.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final duringCheck = shown();

      running.complete();
      await tester.pumpAndSettle();

      expect((duringCheck, shown()), ((1, 2), (1, 2)));
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
      ]);
    });
  });
}

class _TapCountPage extends StatefulWidget {
  const new();

  @override
  State<_TapCountPage> createState() => _TapCountPageState();
}

class _TapCountPageState extends State<_TapCountPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('Account $_count'),
      ),
    ),
  );
}
