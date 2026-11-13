import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard on a tab route can set the tab's children with overrideNext.
// Setup: AppRoute shows tabs: FeedRoute and ProfileRoute. ProfileRoute has
// the children ProfileHomeRoute ('') and ProfileEditRoute ('edit'), and a
// guard that calls resolver.overrideNext(children: [ProfileEditRoute]).
// Steps: open the app and switch to the ProfileRoute tab.
// Was: overrideNext threw "ProfileRoute does not have children" (a null
// check error in release builds). The tabs router gives a tab's guard the
// stack router above the tabs, and overrideNext looked the children up in
// that router's routes, where the tab is not.
// Should: ProfileRoute opens on ProfileEditRoute.
// What this holds to: the doc of NavigationResolver.overrideNext, "Overrides
// the current route with the provided values", which a guard on a stack
// route gets (test/guards/override_children_on_reevaluate_test.dart).
void main() {
  testWidgets('A tab guard can set the children of its tab with overrideNext', (
    tester,
  ) async {
    Object? guardError;
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'AppRoute',
          path: '/',
          builder: (_, _) => const AutoTabsScaffold(
            routes: [NamedRoute('FeedRoute'), NamedRoute('ProfileRoute')],
          ),
          children: [
            _plainRoute('FeedRoute', 'feed'),
            NamedRouteDef.shell(
              name: 'ProfileRoute',
              path: 'profile',
              guards: [
                AutoRouteGuard.simple((resolver, _) {
                  try {
                    resolver.overrideNext(
                      children: [const NamedRoute('ProfileEditRoute')],
                    );
                  } on Object catch (error) {
                    guardError = error;
                    resolver.next();
                  }
                }),
              ],
              children: [
                _plainRoute('ProfileHomeRoute', ''),
                _plainRoute('ProfileEditRoute', 'edit'),
              ],
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());

    router.innerRouterOf<TabsRouter>('AppRoute')!.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(guardError, isNull);
    expect(find.text('ProfileEditRoute'), findsOneWidget);
  });
}

NamedRouteDef _plainRoute(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => Scaffold(body: Center(child: Text(name))),
);
