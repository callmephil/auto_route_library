import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// AutoTabsRouter.pageView built under another page, so never laid out,
// shows the tab chosen meanwhile once it is uncovered, as a covered
// UITabBarController or NavigationBarView does.
// Headless test: auto_route/test/nested_tabs_router/page_view_tabs_under_cover_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('page view tabs under cover', () {
    // Steps: open Other, replaceAll([Home, Details]) so Home's page view is
    // built under Details, navigate to Home's TabC, then close Details.
    // Was: "Null check operator used on a null value", and the tabs showed
    // TabA while the router said TabC was active.
    // Should: no error, and TabC shows.
    testWidgets('A tab chosen while the page view is covered shows', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: AutoTabsRouter.pageView(routes: _kTabs)),
            children: [
              for (final name in ['TabA', 'TabB', 'TabC'])
                NamedRouteDef(
                  name: name,
                  path: name.substring(3).toLowerCase(),
                  builder: (_, _) => Center(child: Text(name)),
                ),
            ],
          ),
          NamedRouteDef(
            name: 'OtherRoute',
            path: '/other',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('OtherRoute'))),
          ),
          NamedRouteDef(
            name: 'DetailsRoute',
            path: '/details',
            builder: (_, _) =>
                const Scaffold(body: SafeArea(child: Text('DetailsRoute'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, initialLink: '/other');

      unawaited(
        router.replaceAll(const [
          NamedRoute('HomeRoute'),
          NamedRoute('DetailsRoute'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('DetailsRoute'), findsOneWidget);

      unawaited(
        router.navigate(
          const NamedRoute('HomeRoute', children: [NamedRoute('TabC')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.innerRouterOf<TabsRouter>('HomeRoute')!.activeIndex, 2);
      expect(find.text('TabC'), findsOneWidget);
      expect(find.text('DetailsRoute'), findsNothing);
    });
  });
}

const List<PageRouteInfo> _kTabs = [
  NamedRoute('TabA'),
  NamedRoute('TabB'),
  NamedRoute('TabC'),
];
