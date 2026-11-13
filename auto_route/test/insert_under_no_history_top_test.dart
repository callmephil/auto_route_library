import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// insert() of a page below the top closed the page on screen when that page
// keeps no history (keepHistory: false).
// Steps: open Home, push SplashRoute, which keeps no history, then call
// insert(SettingsRoute), which goes to the bottom of the stack.
// Native behavior this holds to: Flutter's Navigator keeps the route on top
// when a page is added below it in `pages`, as iOS keeps the top view
// controller when setViewControllers adds one under it. A page that keeps no
// history leaves when another is pushed above it, as an Android activity
// with noHistory finishes when the user leaves it for the next one.
void main() {
  NamedRouteDef page(String name, String path, {bool keepHistory = true}) =>
      .new(
        name: name,
        path: path,
        keepHistory: keepHistory,
        builder: (_, _) => NamedPage(name),
      );

  Future<RootStackRouter> openSplashOverHome(WidgetTester tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('SplashRoute', '/splash', keepHistory: false),
        page('SettingsRoute', '/settings'),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('SplashRoute')));
    await tester.pumpAndSettle();
    return router;
  }

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('insert below a top page that keeps no history keeps that page', (
    tester,
  ) async {
    final router = await openSplashOverHome(tester);

    unawaited(router.insert(const NamedRoute('SettingsRoute')));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['SettingsRoute', 'HomeRoute', 'SplashRoute']);
    expect(find.text('SplashRoute'), findsOneWidget);
    expect(router.currentUrl, '/splash');
  });

  // Steps: the same stack, then insert(SettingsRoute, index: 2), the place
  // above SplashRoute.
  // Was: a RangeError, since SplashRoute had left before the page went in at
  // its index.
  // Should: SettingsRoute goes on top and SplashRoute leaves, as with push.
  testWidgets('insert above a top page that keeps no history takes that page '
      'off', (tester) async {
    final router = await openSplashOverHome(tester);

    Object? error;
    unawaited(
      router
          .insert(const NamedRoute('SettingsRoute'), index: 2)
          .catchError((Object thrown) => error = thrown),
    );
    await tester.pumpAndSettle();

    expect(error, isNull);
    expect(stackNames(router), ['HomeRoute', 'SettingsRoute']);
    expect(find.text('SettingsRoute'), findsOneWidget);
  });
}
