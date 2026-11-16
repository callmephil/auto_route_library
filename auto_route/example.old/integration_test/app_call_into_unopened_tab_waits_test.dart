import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The app's own navigatePath into a tab never opened, to a page whose guard
// says no, keeps the tab the user is on: the tab is built off the screen and
// shows only once the guard lets the navigation in, as a link's tab does.
// Native behavior this holds to: UITabBarController changes its tab when
// selectedViewController or selectedIndex is assigned (Apple docs); that a
// refused call leaves the tab as it is is this package's own rule. On the
// web a canceled navigation leaves the document on screen (HTML standard,
// navigate event).
// Headless test:
// auto_route/test/nested_tabs_router/app_call_into_unopened_tab_waits_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('app call into unopened tab waits', () {
    Widget page(String name) => Scaffold(
      body: SafeArea(child: Center(child: Text(name))),
    );

    // Steps: the tabs show FirstTab; MailTab was never opened. The app calls
    // navigatePath to message 13 in MailTab, whose guard says no.
    // Was: MailTab showed its inbox, at its url.
    // Should: FirstTab stays, at its url.
    testWidgets('A path into a tab never opened, rejected, keeps the tab', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'TabsRoute',
            path: '/tabs',
            initial: true,
            builder: (_, _) => const AutoTabsRouter(
              routes: [NamedRoute('FirstTab'), NamedRoute('MailTab')],
            ),
            children: [
              NamedRouteDef(
                name: 'FirstTab',
                path: 'first',
                builder: (_, _) => page('FirstTab'),
              ),
              NamedRouteDef.shell(
                name: 'MailTab',
                path: 'mail',
                children: [
                  NamedRouteDef(
                    name: 'InboxRoute',
                    path: '',
                    builder: (_, _) => page('InboxRoute'),
                  ),
                  NamedRouteDef(
                    name: 'MessageRoute',
                    path: ':id',
                    guards: [
                      AutoRouteGuard.simple(
                        (resolver, _) => resolver.reject(),
                      ),
                    ],
                    builder: (_, _) => page('MessageRoute'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      unawaited(router.navigatePath('/tabs/mail/13'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('FirstTab'), findsOneWidget);
      expect(find.text('InboxRoute'), findsNothing);
      expect(router.currentUrl, '/tabs/first');
      await expectBrowserUrl('/tabs/first');
    });
  });
}
