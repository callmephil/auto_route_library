import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigation to a tab never shown, naming no children, opens the tab with
// the children the tabs list gave it.
// Headless test: auto_route/test/nested_tabs_router/
// navigate_to_unshown_tab_keeps_children_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigate to unshown tab keeps children', () {
    // Steps: tabs [FeedTab, ProfileTab(children: [ProfileInfo])]; ProfileTab
    // has no initial child. Tap 'Open profile', which calls
    // tabs.navigate(ProfileTab()) with no children.
    // Was: ProfileTab opened empty.
    // Should: ProfileTab opens on ProfileInfo, as UIKit's tab bar controller
    // shows a tab's view controller as the app set it up.
    testWidgets('navigate with no children opens the listed children', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter(
                routes: [
                  NamedRoute('FeedTab'),
                  NamedRoute(
                    'ProfileTab',
                    children: [NamedRoute('ProfileInfo')],
                  ),
                ],
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'FeedTab',
                path: 'feed',
                builder: (context, _) => SafeArea(
                  child: TextButton(
                    onPressed: () => context.tabsRouter.navigate(
                      const NamedRoute('ProfileTab'),
                    ),
                    child: const Text('Open profile'),
                  ),
                ),
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
                      builder: (_, _) => SafeArea(child: Text(name)),
                    ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      await tester.tap(find.text('Open profile'));
      await tester.pumpAndSettle();

      expect(find.text('ProfileInfo'), findsOneWidget);
      expect(router.urlState.url, '/profile/info');
    });
  });
}
