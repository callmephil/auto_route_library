import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

// The pages stay on screen, with their State, while a guard of replaceAll
// decides, and a rejection changes nothing, as iOS swaps a navigation stack
// in one step and Flutter's Router keeps building the current pages while its
// delegate waits.
// Headless test: auto_route/test/guards/replace_all_slow_guard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all slow guard', () {
    // Steps: open Home, push Form and tap it once. Then replaceAll with the
    // Guarded route, whose async guard waits. The widget above
    // MaterialApp.router rebuilds meanwhile, as on a theme change. The guard
    // rejects.
    // Was: a blank screen while the guard decided, then Form back with its
    // count at 0.
    // Should: Form stays on screen with its count, during the wait and after
    // the rejection.
    testWidgets('The pages stay on screen while a guard of replaceAll '
        'decides, and keep their State when it rejects', (tester) async {
      final decision = Completer<bool>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
          ),
          NamedRouteDef(
            name: 'FormRoute',
            path: '/form',
            builder: (_, _) => const _TapCountPage(),
          ),
          NamedRouteDef(
            name: 'GuardedRoute',
            path: '/guarded',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                if (await decision.future) {
                  resolver.next();
                } else {
                  resolver.reject();
                }
              }),
            ],
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('GuardedRoute'))),
          ),
        ],
      );
      final config = router.config(
        deepLinkBuilder: (link) => link.initial ? DeepLink.defaultPath : link,
      );
      addTearDown(router.dispose);
      var brightness = Brightness.light;
      late StateSetter setAppState;
      tester.binding.handleAppLifecycleStateChanged(.resumed);
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setAppState = setState;
            return MaterialApp.router(
              theme: ThemeData(brightness: brightness),
              routerConfig: config,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('FormRoute')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Form 0'));
      await tester.pumpAndSettle();

      unawaited(router.replaceAll([const NamedRoute('GuardedRoute')]));
      await tester.pump();
      setAppState(() => brightness = .dark);
      await tester.pumpAndSettle();

      // Form on screen with its count, and the pages on the stack.
      (int, int) shown() =>
          (find.text('Form 1').evaluate().length, router.stack.length);
      final whileDeciding = shown();

      decision.complete(false);
      await tester.pumpAndSettle();

      expect((whileDeciding, shown()), ((1, 2), (1, 2)));
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'FormRoute']);
      expect(find.text('GuardedRoute'), findsNothing);
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
        child: Text('Form $_count'),
      ),
    ),
  );
}
