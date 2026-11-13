import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A tab's page built under another page by a deep link hears didPushNext,
// so the didPopNext it hears when that page is popped has its pair.
// Steps: '/' hosts tabs, Tab1 with AutoRouteAwareStateMixin; '/b' is a page.
// Open the app at the deep link '/b', which stacks B on the tabs, then pop B.
// Before the fix, Tab1 heard didInitTabRoute and then, on the pop,
// didPopNext with no didPushNext before it: the branch of
// AutoRouteObserver.subscribe for a tab page skipped the check for a page
// built while covered that a stack page gets. The control test pushes B over
// the tabs in the running app.
// Native behavior this holds to: Flutter's RouteAware pairs every didPopNext
// with an earlier didPushNext (widgets/routes.dart, RouteObserver.didPush and
// didPop), and the README says "A page built while covered, such as the
// pages a deep link stacks under its top page, hears didPush and then
// didPushNext."
final _events = <String>[];

class _AwarePage extends StatefulWidget {
  const new();

  @override
  State<_AwarePage> createState() => _AwarePageState();
}

class _AwarePageState extends State<_AwarePage>
    with AutoRouteAwareStateMixin<_AwarePage> {
  late final String _name = context.routeData.name;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(_name));

  @override
  void didPush() => _events.add('$_name.didPush');

  @override
  void didPop() => _events.add('$_name.didPop');

  @override
  void didPushNext() => _events.add('$_name.didPushNext');

  @override
  void didPopNext() => _events.add('$_name.didPopNext');

  @override
  void didInitTabRoute(TabPageRoute? previousRoute) =>
      _events.add('$_name.didInitTabRoute');
}

RootStackRouter _buildRouter() => .build(
  routes: [
    AutoRoute(
      path: '/',
      page: PageInfo(
        'TabsRoute',
        builder: (_) => const AutoTabsRouter(
          routes: [NamedRoute('Tab1'), NamedRoute('Tab2')],
        ),
      ),
      children: [
        AutoRoute(
          path: '',
          page: PageInfo('Tab1', builder: (_) => const _AwarePage()),
        ),
        AutoRoute(
          path: 'tab2',
          page: PageInfo('Tab2', builder: (_) => const _AwarePage()),
        ),
      ],
    ),
    AutoRoute(
      path: '/b',
      page: PageInfo('B', builder: (_) => const _AwarePage()),
    ),
  ],
);

void main() {
  testWidgets(
    "Control: a tab's page hears a page pushed over the tabs, and its pop",
    (tester) async {
      final router = _buildRouter();
      _events.clear();
      await pumpRouterConfigApp(
        tester,
        router.config(navigatorObservers: () => [AutoRouteObserver()]),
      );
      expect(_events, ['Tab1.didInitTabRoute']);

      _events.clear();
      unawaited(router.push(const NamedRoute('B')));
      await tester.pumpAndSettle();
      expect(_events, ['Tab1.didPushNext', 'B.didPush']);

      _events.clear();
      router.pop();
      await tester.pumpAndSettle();
      expect(_events, ['B.didPop', 'Tab1.didPopNext']);
    },
  );

  testWidgets(
    "A tab's page built under another page by a deep link hears didPushNext",
    (tester) async {
      final router = _buildRouter();
      _events.clear();
      await pumpRouterConfigApp(
        tester,
        router.config(
          navigatorObservers: () => [AutoRouteObserver()],
          deepLinkBuilder: (_) => const DeepLink.path('/b'),
        ),
      );
      expect(router.stack.map((page) => page.name), ['TabsRoute', 'B']);
      final afterStart = List.of(_events);

      _events.clear();
      router.pop();
      await tester.pumpAndSettle();
      // The pop tells Tab1 it shows again, so the start must have told it
      // that it was covered.
      expect(_events, ['B.didPop', 'Tab1.didPopNext']);
      expect(afterStart, contains('Tab1.didPushNext'));
    },
  );
}
