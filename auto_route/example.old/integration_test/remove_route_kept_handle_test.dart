import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/init_count_page.dart';
import 'support/pages.dart';

// removeRoute with the RouteData of a screen kept from before a navigation
// reached that screen again removes the screen, as the app's own removal.
// Headless test:
// auto_route/test/simple_router/remove_route_kept_handle_test.dart
// Flutter's Navigator.removeRoute removes the route it kept for a page of the
// same key and type, and Android's finishActivity(requestCode) finishes a
// single-top activity that a new intent reached again.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Steps: push ScreenRoute, keep router.topRoute, navigate to ScreenRoute
  // with a new query param, then removeRoute with the kept RouteData and push
  // ScreenRoute in one go.
  // Happened: the push took over the screen just removed, with its state.
  // Should: a new page, as after removeRoute with the RouteData on show.
  testWidgets('removeRoute by kept RouteData, then a push, builds a new page', (
    tester,
  ) async {
    var screenInits = 0;
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const TextPage('Home'),
        ),
        NamedRouteDef(
          name: 'ScreenRoute',
          path: '/screen',
          builder: (_, _) =>
              InitCountPage(() => screenInits++, label: 'Screen'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('ScreenRoute')));
    await tester.pumpAndSettle();
    final kept = router.topRoute;
    unawaited(
      router.navigate(
        const NamedRoute('ScreenRoute', queryParams: {'q': '1'}),
      ),
    );
    await tester.pumpAndSettle();
    await expectBrowserUrl('/screen?q=1');
    expect(screenInits, 1);

    router.removeRoute(kept);
    unawaited(router.push(const NamedRoute('ScreenRoute')));
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.name), ['HomeRoute', 'ScreenRoute']);
    expect(find.text('Screen'), findsOneWidget);
    await expectBrowserUrl('/screen');
    expect(screenInits, 2);
  });
}
