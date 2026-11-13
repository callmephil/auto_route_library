import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A navigation to a tab never shown, naming no children, opens the tab with
// the children the tabs list gave it.
// Setup: tabs [FeedTab, ProfileTab(children: [ProfileInfo])]. ProfileTab
// holds a nested router with ProfileInfo and ProfileEdit, and no initial
// child.
// Steps: on FeedTab, call tabs.navigate(ProfileTab()) with no children.
// Was: ProfileTab opened with its nested router empty: the navigation's
// route, with no children, took the place of the listed one.
// Should: ProfileTab opens on ProfileInfo, also when the root navigates to
// HomeRoute with ProfileTab; a navigation that names children still opens
// those. A path names the whole state: navigatePath('/profile') opens the
// tab with no page, as it does for a tab already shown, where it empties
// the nested router.
// Native behavior this holds to: selecting a tab in UIKit's
// UITabBarController shows that tab's view controller as the app set it up,
// a navigation controller with its stack. Choosing a tab never shows it
// empty.
void main() {
  testWidgets('navigate with no children opens the listed children', (
    tester,
  ) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

    unawaited(tabs.navigate(const NamedRoute('ProfileTab')));
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 1);
    expect(find.text('ProfileInfo'), findsOneWidget);
    expect(router.urlState.url, '/profile/info');
  });

  testWidgets('root navigate with no children opens the listed children', (
    tester,
  ) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

    unawaited(
      router.navigate(
        const NamedRoute('HomeRoute', children: [NamedRoute('ProfileTab')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 1);
    expect(find.text('ProfileInfo'), findsOneWidget);
    expect(router.urlState.url, '/profile/info');
  });

  // On the web a url is the whole state: '/profile' names no page inside the
  // tab, so the tab shows none.
  testWidgets('navigatePath with no child opens the tab with no page', (
    tester,
  ) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

    unawaited(router.navigatePath('/profile'));
    await tester.pumpAndSettle();

    expect(tabs.activeIndex, 1);
    expect(find.text('ProfileInfo'), findsNothing);
    expect(router.urlState.url, '/profile');
  });

  testWidgets('navigate with children opens those children', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

    unawaited(
      tabs.navigate(
        const NamedRoute('ProfileTab', children: [NamedRoute('ProfileEdit')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ProfileEdit'), findsOneWidget);
    expect(find.text('ProfileInfo'), findsNothing);
    expect(router.urlState.url, '/profile/edit');
  });
}

RootStackRouter _buildRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const AutoTabsRouter(
        routes: [
          NamedRoute('FeedTab'),
          NamedRoute('ProfileTab', children: [NamedRoute('ProfileInfo')]),
        ],
      ),
      children: [
        NamedRouteDef(
          name: 'FeedTab',
          path: 'feed',
          builder: (_, _) => const Center(child: Text('FeedTab')),
        ),
        NamedRouteDef.shell(
          name: 'ProfileTab',
          path: 'profile',
          children: [
            for (final (name, path) in [
              ('ProfileInfo', 'info'),
              ('ProfileEdit', 'edit'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => Center(child: Text(name)),
              ),
          ],
        ),
      ],
    ),
  ],
);
