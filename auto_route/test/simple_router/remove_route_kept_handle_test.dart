import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../init_count_page.dart';
import '../router_test_utils.dart';

// removeRoute with the RouteData of a screen kept from before a navigation
// reached that screen again. The navigation keeps the screen, its state and
// its match id, so the kept RouteData still names the screen on show, and the
// screen's own state still holds it. Native navigation removes the screen for
// such a handle: Flutter's Navigator.removeRoute removes the route it kept for
// a page of the same key and type, and Android's finishActivity(requestCode)
// finishes a single-top activity that a new intent reached again, whose
// record keeps the caller and request code.

const NamedRoute<Object?> _screen = NamedRoute('ScreenRoute');
const NamedRoute<Object?> _screenAgain = NamedRoute(
  'ScreenRoute',
  queryParams: {'q': '1'},
);

RootStackRouter _buildRouter(VoidCallback onScreenInit) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('Home'),
    ),
    NamedRouteDef(
      name: 'ScreenRoute',
      path: '/screen',
      builder: (_, _) => InitCountPage(onScreenInit, label: 'Screen'),
    ),
  ],
);

void main() {
  // Steps: push ScreenRoute with push<int>, keep router.topRoute, navigate to
  // ScreenRoute with a new query param, as a link to it does, then
  // removeRoute with the kept RouteData.
  // Should: the screen leaves, as it already did: the kept RouteData names the
  // screen the navigation kept, with its state, so it isn't a stale handle.
  // The push answers null, as for any screen the app removes.
  testWidgets(
    'removeRoute by kept RouteData removes the screen reached again',
    (tester) async {
      var screenInits = 0;
      final router = _buildRouter(() => screenInits++);
      await pumpRouterApp(tester, router);
      var result = 'waiting';
      unawaited(
        router
            .push<int>(_screen)
            .then((value) => result = 'got ${value ?? 'null'}'),
      );
      await tester.pumpAndSettle();
      final kept = router.topRoute;

      unawaited(router.navigate(_screenAgain));
      await tester.pumpAndSettle();
      expect(router.topRoute, isNot(same(kept)));
      expect(router.currentUrl, '/screen?q=1');
      expect(screenInits, 1);

      router.removeRoute(kept);
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Screen'), findsNothing);
      expect(router.currentUrl, '/');
      expect(result, 'got null');
    },
  );

  // Steps: push ScreenRoute, keep router.topRoute, navigate to ScreenRoute
  // with a new query param, then removeRoute with the kept RouteData and push
  // ScreenRoute in one go.
  // Happened: the push took over the screen just removed, with its state, so
  // the screen's initState ran once. removeRoute marked only a page built for
  // the kept RouteData as removed by the app, and the screen now showed
  // another page.
  // Should: a new page, as after removeRoute with the RouteData on show and
  // as #1204 settled for any page the app removes: initState runs again.
  testWidgets('removeRoute by kept RouteData, then a push, builds a new page', (
    tester,
  ) async {
    var screenInits = 0;
    final router = _buildRouter(() => screenInits++);
    await pumpRouterApp(tester, router);
    unawaited(router.push(_screen));
    await tester.pumpAndSettle();
    final kept = router.topRoute;
    unawaited(router.navigate(_screenAgain));
    await tester.pumpAndSettle();
    expect(screenInits, 1);

    router.removeRoute(kept);
    unawaited(router.push(_screen));
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.name), ['HomeRoute', 'ScreenRoute']);
    expect(find.text('Screen'), findsOneWidget);
    expect(router.currentUrl, '/screen');
    expect(screenInits, 2);
  });
}
