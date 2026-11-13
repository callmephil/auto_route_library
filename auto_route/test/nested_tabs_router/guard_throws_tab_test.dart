import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab whose guard threw once opens when it is chosen again.
// Setup: tabs [TabA, TabB]. TabB's guard awaits a check that fails the first
// time, as a request does while the phone is offline, and lets the tab in
// from then on.
// Steps: choose TabB with setActiveIndex(1): the guard throws and TabA stays.
// Choose TabB again.
// Was: nothing happened, and the guard was not asked: the tab change whose
// guard threw stayed the waiting one, so every later change to TabB got its
// failed future, until another tab was opened first. The guard also stayed
// in activeGuardObserver, so guardInProgress stayed true.
// Should: the change whose guard threw is over; the second choice asks the
// guard again, and TabB shows.
// Native behavior this holds to: a navigation whose handler fails is over,
// and the next one starts anew. On the web a failed navigation fires
// navigateerror and ends (MDN, Navigation: navigateerror event). The control
// shows the fork's stack router doing that with the same guard.
void main() {
  setUp(() {
    _guardCalls = 0;
    _doesCheckFail = true;
  });

  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a tab whose guard threw once opens when chosen again',
      (tester) async {
        final router = _buildRouter(kind);
        await pumpRouterApp(tester, router);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

        // setActiveIndex returns nothing, so the guard's error is uncaught.
        final errors = <Object>[];
        await runZonedGuarded(() async {
          tabs.setActiveIndex(1);
          await tester.pumpAndSettle();
        }, (error, _) => errors.add(error));
        expect(errors, [isStateError]);
        expect(_guardCalls, 1);
        expect(tabs.activeIndex, 0);
        expect(router.activeGuardObserver.guardInProgress, isFalse);

        _doesCheckFail = false;
        await runZonedGuarded(() async {
          tabs.setActiveIndex(1);
          await tester.pumpAndSettle();
        }, (error, _) => errors.add(error));

        expect(_guardCalls, 2);
        expect(tabs.activeIndex, 1);
        expect(find.text('TabB'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'control: a stack route whose guard threw once opens when pushed again',
    (tester) async {
      final router = _buildRouter(.indexedStack);
      await pumpRouterApp(tester, router);

      Object? error;
      unawaited(
        router
            .push(const NamedRoute('GuardedRoute'))
            .then<void>(
              (_) => fail('the push should fail'),
              onError: (Object e) => error = e,
            ),
      );
      await tester.pumpAndSettle();
      expect(error, isStateError);
      expect(_guardCalls, 1);

      _doesCheckFail = false;
      unawaited(router.push(const NamedRoute('GuardedRoute')));
      await tester.pumpAndSettle();

      expect(_guardCalls, 2);
      expect(find.text('GuardedRoute'), findsOneWidget);
    },
  );
}

enum _Tabs { indexedStack, pageView, tabBar }

var _guardCalls = 0;
var _doesCheckFail = true;

final _guard = AutoRouteGuard.simple((resolver, _) async {
  _guardCalls++;
  // Stands for a request that fails.
  await Future<void>.delayed(.zero);
  if (_doesCheckFail) throw StateError('offline');
  resolver.next();
});

RootStackRouter _buildRouter(_Tabs kind) {
  const routes = [NamedRoute<Object?>('TabA'), NamedRoute<Object?>('TabB')];
  return .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .indexedStack => const AutoTabsRouter(routes: routes),
            .pageView => const AutoTabsRouter.pageView(routes: routes),
            .tabBar => const AutoTabsRouter.tabBar(routes: routes),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'TabA',
            path: 'a',
            builder: (_, _) => const Center(child: Text('TabA')),
          ),
          NamedRouteDef(
            name: 'TabB',
            path: 'b',
            guards: [_guard],
            builder: (_, _) => const Center(child: Text('TabB')),
          ),
        ],
      ),
      NamedRouteDef(
        name: 'GuardedRoute',
        path: '/guarded',
        guards: [_guard],
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('GuardedRoute'))),
      ),
    ],
  );
}
