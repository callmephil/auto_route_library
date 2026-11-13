import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

// The pages of a batch stay off the screen until every guard has answered,
// then go on together or not at all, as Flutter's Navigator takes a new list
// of pages as one update and Android applies a fragment transaction as one
// atomic set of operations.
// Headless test: auto_route/test/guards/batch_slow_guard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('batch slow guard', () {
    // Steps: open Home. pushAll([List, Checkout]), where Checkout's async
    // guard waits. The widget above MaterialApp.router rebuilds meanwhile, as
    // on a theme change. The guard rejects.
    // Was: List showed while the guard decided, and left again when it
    // rejected.
    // Should: Home stays on screen, during the wait and after the rejection.
    testWidgets('The pages of a batch stay off the screen while a later guard '
        'decides', (tester) async {
      final decision = Completer<bool>();
      Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'ListRoute',
            path: '/list',
            builder: (_, _) => page('ListRoute'),
          ),
          NamedRouteDef(
            name: 'CheckoutRoute',
            path: '/checkout',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                if (await decision.future) {
                  resolver.next();
                } else {
                  resolver.reject();
                }
              }),
            ],
            builder: (_, _) => page('CheckoutRoute'),
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

      unawaited(
        router.pushAll(const [
          NamedRoute('ListRoute'),
          NamedRoute('CheckoutRoute'),
        ]),
      );
      await tester.pump();
      setAppState(() => brightness = .dark);
      await tester.pumpAndSettle();

      // Home and List on screen, and the pages on the stack.
      (int, int, int) shown() => (
        find.text('HomeRoute').evaluate().length,
        find.text('ListRoute').evaluate().length,
        router.stack.length,
      );
      final whileDeciding = shown();

      decision.complete(false);
      await tester.pumpAndSettle();

      expect((whileDeciding, shown()), ((1, 0, 1), (1, 0, 1)));
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
    });
  });
}
