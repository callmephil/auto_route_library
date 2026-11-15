import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Found while fixing the guard issues, no upstream issue.
// Steps: the router has a reevaluateListenable. The app's first route is
// guarded by AutoRouteGuard.simple with an async callback that waits before it
// calls resolver.next(). Fire the listenable while the callback still waits.
// Was: the re-check called the callback a second time, because the simple
// guard dropped the callback's future, and the second resolver.next() failed
// "Make sure `resolver.next()` is only called once."
// Should: the re-check waits for the running callback and starts no second
// call beside it, and the guarded page opens. The change came while the
// guard ran its check, so once that call has answered the guard is asked
// once more before its page goes in: two calls, one after the other. See
// reevaluatable_router/change_during_navigation_guard_test.dart.
void main() {
  testWidgets(
    'a guard re-check waits for an async simple guard still running',
    (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/profile';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      var guardCalls = 0;
      final auth = ValueNotifier(0);
      addTearDown(auth.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
          ),
          NamedRouteDef(
            name: 'ProfileRoute',
            path: '/profile',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                guardCalls++;
                await Future<void>.delayed(const Duration(milliseconds: 100));
                resolver.next();
              }),
            ],
            builder: (_, _) => const Scaffold(body: Text('ProfileRoute')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router.config(reevaluateListenable: auth),
        ),
      );
      auth.value++;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(guardCalls, 2);
      expect(router.topRoute.name, 'ProfileRoute');
      expect(find.text('ProfileRoute'), findsOneWidget);
    },
  );
}
