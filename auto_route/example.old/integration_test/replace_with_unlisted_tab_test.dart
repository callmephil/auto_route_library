import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Headless test:
// auto_route/test/nested_tabs_router/replace_with_unlisted_tab_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // https://github.com/callmephil/auto_route_library/issues/15
  // replace, replacePath and replaceAll to a tabs page that is not open, with
  // a tab that its AutoTabsRouter does not list, removed the page on top and
  // opened the tabs page on its first tab. push with the same route changed
  // nothing.
  // Steps: LandingRoute at '/', push DetailRoute, then replacePath
  // '/home/profile'. HomeRoute's tabs list holds FeedTab and SettingsTab,
  // not ProfileTab.
  // Native: Android's NavController.navigate to a destination that its graph
  // does not hold throws IllegalArgumentException before it changes the back
  // stack, also when its NavOptions pop destinations. UITabBarController
  // selects only a view controller in its viewControllers array.
  RootStackRouter buildRouter() => .build(
    routes: [
      NamedRouteDef(
        name: 'LandingRoute',
        path: '/',
        builder: (_, _) => const Text('Landing'),
      ),
      NamedRouteDef(
        name: 'DetailRoute',
        path: '/detail',
        builder: (_, _) => const Text('Detail'),
      ),
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/home',
        builder: (_, _) => const Scaffold(
          body: AutoTabsRouter(
            routes: [NamedRoute('FeedTab'), NamedRoute('SettingsTab')],
          ),
        ),
        children: [
          NamedRouteDef(
            name: 'FeedTab',
            path: 'feed',
            builder: (_, _) => const Text('Feed'),
          ),
          NamedRouteDef(
            name: 'ProfileTab',
            path: 'profile',
            builder: (_, _) => const Text('Profile'),
          ),
          NamedRouteDef(
            name: 'SettingsTab',
            path: 'settings',
            builder: (_, _) => const Text('Settings'),
          ),
        ],
      ),
    ],
  );

  const target = NamedRoute('HomeRoute', children: [NamedRoute('ProfileTab')]);

  final calls =
      <
        String,
        Future<Object?> Function(
          RootStackRouter, {
          OnNavigationFailure? onFailure,
        })
      >{
        'replacePath': (r, {onFailure}) =>
            r.replacePath('/home/profile', onFailure: onFailure),
        'replace': (r, {onFailure}) => r.replace(target, onFailure: onFailure),
        'replaceAll': (r, {onFailure}) =>
            r.replaceAll([target], onFailure: onFailure),
      };

  for (final MapEntry(:key, :value) in calls.entries) {
    group(key, () {
      Future<RootStackRouter> start(WidgetTester tester) async {
        final router = buildRouter();
        await pumpRouterApp(tester, router);
        unawaited(router.push(const NamedRoute('DetailRoute')));
        await tester.pumpAndSettle();
        return router;
      }

      testWidgets('changes nothing and reports the failure', (tester) async {
        final router = await start(tester);
        final names = router.stack.map((p) => p.name).toList();
        final entries = router.navigationHistory.length;
        final url = router.currentUrl;
        final failures = <NavigationFailure>[];

        unawaited(value(router, onFailure: failures.add));
        await tester.pumpAndSettle();

        expect(failures, hasLength(1));
        expect(failures.singleOrNull, isA<RouteNotFoundFailure>());
        expect(router.stack.map((p) => p.name), names);
        expect(find.text('Detail'), findsOneWidget);
        expect(router.currentUrl, url);
        expect(router.navigationHistory.length, entries);
      });

      testWidgets('throws without onFailure, changes nothing', (tester) async {
        final router = await start(tester);
        final names = router.stack.map((p) => p.name).toList();
        final entries = router.navigationHistory.length;
        final url = router.currentUrl;

        Object? error;
        unawaited(
          value(router)
              .then<Object?>((_) => null, onError: (Object e) => error = e),
        );
        await tester.pumpAndSettle();

        expect(error, isA<FlutterError>());

        expect(router.stack.map((p) => p.name), names);
        expect(find.text('Detail'), findsOneWidget);
        expect(router.currentUrl, url);
        expect(router.navigationHistory.length, entries);
      });
    });
  }
}
