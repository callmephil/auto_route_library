import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// callmephil/auto_route_library#8: a link the router turns down leaves the
// route data of the open page as it was.
// Steps: Home holds the tabs Feed and Settings; Profile is a child route of
// Home that the app removed from its tabs. Select Settings, then open the
// link '/profile?ref=mail#top'. Read router.current and the children of
// Home's route; then select Feed and read them again.
// Was: router.current.queryParams was {ref: mail}, its fragment 'top', and
// Home's route named Profile as its child, also after Feed was selected.
// Should: Settings at '/settings', with the query, fragment and children of
// before.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document, its url and its state as they were (HTML standard). On
// Android, a navigation NavController does not perform leaves
// currentBackStackEntry and its arguments as they were.
// Headless test:
// auto_route/test/guards/rejected_nested_navigation_keeps_route_data_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => SafeArea(child: Center(child: Text(name)));

  // Hands [location] to the running app the way the engine does when the
  // platform opens a link.
  Future<void> openLink(WidgetTester tester, String location) async {
    const codec = JSONMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': location,
          'state': null,
        }),
      ),
      null,
    );
    await tester.pumpAndSettle();
  }

  group('rejected nested navigation keeps route data', () {
    testWidgets('A link to a removed tab keeps the route data of Home', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter(
                routes: [NamedRoute('FeedTab'), NamedRoute('SettingsTab')],
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'FeedTab',
                path: 'feed',
                builder: (_, _) => page('Feed'),
              ),
              NamedRouteDef(
                name: 'ProfileTab',
                path: 'profile',
                builder: (_, _) => page('Profile'),
              ),
              NamedRouteDef(
                name: 'SettingsTab',
                path: 'settings',
                builder: (_, _) => page('Settings'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!
        ..setActiveIndex(1);
      await tester.pumpAndSettle();

      await openLink(tester, '/profile?ref=mail#top');

      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
      expect(router.currentUrl, '/settings');
      expect(router.current.queryParams.rawMap, isEmpty);
      expect(router.current.fragment, isEmpty);
      final children = router.stackData.firstOrNull?.route.children ?? const [];
      expect(
        children.map((child) => child.name),
        isNot(contains('ProfileTab')),
      );

      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/feed');
      expect(router.current.queryParams.rawMap, const <String, Object?>{});
      await expectBrowserUrl('/feed');
    });
  });
}
