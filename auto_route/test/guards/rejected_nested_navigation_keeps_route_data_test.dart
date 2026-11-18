import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// callmephil/auto_route_library#8: after a navigation into the nested
// router of an open page was turned down, the route data of that page held
// the refused child route and the navigation's query and fragment.
// Setup: Home at '/' holds the tabs Feed and Settings; Profile is a child
// route of Home that the app removed from its tabs. Mail at '/mail' holds a
// stack router with Inbox at '' and Message at ':id', whose guard the test
// answers.
// Steps: select Settings, then open '/profile?ref=mail#top' as a link, or
// navigate or navigatePath to it; or, with Mail open, go to
// '/mail/77?ref=mail#top' and the guard says no. Read the route data of the
// open page, then select another tab or not.
// Was: the screen and the url stayed, but router.current.queryParams was
// {ref: mail}, its fragment 'top', and the children of the open page named
// Profile or Message, also after the user selected Feed.
// Should: the route data of the open page is as before the navigation.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document, its url and its state as they were (HTML standard, the
// navigate algorithm). On Android, a navigation that NavController does not
// perform leaves currentBackStackEntry and its arguments as they were.
final _guard = HeldGuard();

// What the calls hear of their failures.
final _failures = <NavigationFailure>[];

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const AutoTabsRouter(
        routes: [NamedRoute('FeedTab'), NamedRoute('SettingsTab')],
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
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'InboxRoute',
          path: '',
          builder: (_, _) => const Text('Inbox'),
        ),
        NamedRouteDef(
          name: 'MessageRoute',
          path: ':id',
          guards: [_guard],
          builder: (_, _) => const Text('Message'),
        ),
      ],
    ),
  ],
);

enum _Way { link, navigatePath, navigate }

// What the test reads of the open page: the query and fragment of
// router.current, and the names of the children of the top page's route.
Map<String, Object?> _dataOf(RootStackRouter router) => {
  'query': router.current.queryParams.rawMap,
  'fragment': router.current.fragment,
  'children': router.stackData.lastOrNull?.route.children
      ?.map((child) => child.name)
      .toList(),
};

Future<void> _go(
  WidgetTester tester,
  RootStackRouter router,
  _Way way,
  String path,
  PageRouteInfo route,
) async {
  switch (way) {
    case .link:
      unawaited(tester.binding.handlePushRoute(path));
    case .navigatePath:
      unawaited(router.navigatePath(path, onFailure: _failures.add));
    case .navigate:
      unawaited(router.navigate(route, onFailure: _failures.add));
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final way in _Way.values) {
    testWidgets('${way.name} to a tab the app removed keeps the route data '
        'of Home', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
        ..setActiveIndex(1);
      await tester.pumpAndSettle();
      final before = _dataOf(router);

      await _go(
        tester,
        router,
        way,
        '/profile?ref=mail#top',
        const NamedRoute(
          'HomeRoute',
          children: [
            NamedRoute(
              'ProfileTab',
              queryParams: {'ref': 'mail'},
              fragment: 'top',
            ),
          ],
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(router.currentUrl, '/settings');
      expect(_dataOf(router), before);

      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/feed');
      expect(router.current.queryParams.rawMap, isEmpty);
      expect(
        router.stackData.firstOrNull?.route.children?.map((c) => c.name),
        isNot(contains('ProfileTab')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('${way.name} into open Mail, its guard says no, keeps the '
        'route data of Mail', (tester) async {
      _guard
        ..clear()
        ..holdCall();
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.navigatePath('/mail'));
      await tester.pumpAndSettle();
      final before = _dataOf(router);

      await _go(
        tester,
        router,
        way,
        '/mail/77?ref=mail#top',
        const NamedRoute(
          'MailRoute',
          children: [
            NamedRoute(
              'MessageRoute',
              params: {'id': '77'},
              queryParams: {'ref': 'mail'},
              fragment: 'top',
            ),
          ],
        ),
      );
      expect(_guard.askCount, 1);
      await _guard.last.reject();
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
      expect(router.currentUrl, '/mail');
      expect(_dataOf(router), before);
      expect(tester.takeException(), isNull);
    });
  }
}
