import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// parentAsStackRouter and parent<StackRouter>() threw a type error for the
// router of a tab, whose parent is a tabs router, in place of answering
// null.
// Setup: AppRoute shows tabs; the tab ProfileRoute holds a nested router
// with ProfileHomeRoute.
// Steps: read parentAsStackRouter, parent<StackRouter>() and
// parent<TabsRouter>() on the tab's nested router and on the tabs router.
// Native behavior this holds to: a lookup of the container of one kind
// answers null when the container is of another kind. On iOS a view
// controller's navigationController is nil when no navigation controller
// holds it, and Flutter's Navigator.maybeOf and
// findAncestorStateOfType answer null when there is none of that type.
void main() {
  NamedRouteDef page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => NamedPage(name));

  testWidgets('parent answers null for a parent router of another kind', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'AppRoute',
          path: '/',
          builder: (_, _) => const AutoTabsScaffold(
            routes: [NamedRoute('ProfileRoute'), NamedRoute('FeedRoute')],
          ),
          children: [
            NamedRouteDef.shell(
              name: 'ProfileRoute',
              path: 'profile',
              children: [page('ProfileHomeRoute', '')],
            ),
            page('FeedRoute', 'feed'),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    final tabs = router.innerRouterOf<TabsRouter>('AppRoute')!;
    final profile = tabs.innerRouterOf<StackRouter>('ProfileRoute')!;

    expect(profile.parent<TabsRouter>(), tabs);
    expect(profile.parentAsStackRouter, isNull);
    expect(profile.parent<StackRouter>(), isNull);
    expect(tabs.parentAsStackRouter, router);
    expect(tabs.parent<TabsRouter>(), isNull);
    expect(router.parent<StackRouter>(), isNull);
  });
}
