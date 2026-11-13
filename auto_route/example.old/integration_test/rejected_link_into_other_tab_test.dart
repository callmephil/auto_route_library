import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link to a page inside another tab, which that page's guard rejects,
// keeps the tab on screen and the dialog the user has open; a link to a page
// there that the app lets in shows the tab and closes the dialog.
// Headless test:
// auto_route/test/nested_tabs_router/rejected_link_into_other_tab_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => Scaffold(
    body: SafeArea(child: Center(child: Text(name))),
  );

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

  group('rejected link into other tab', () {
    // Steps: the app shows the tabs on FirstTab with a dialog open; the mail
    // tab was never opened. The platform hands the running app a link to
    // message 13 in the mail tab, which its guard rejects, then a link to
    // message 7, which the app lets in.
    // Was: the rejected link closed the dialog and showed the mail tab.
    // Should: FirstTab and the dialog stay after message 13; message 7
    // shows the mail tab and closes the dialog.
    testWidgets(
      'A link a guard in another tab rejects keeps the tab and the dialog',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'TabsRoute',
              path: '/tabs',
              initial: true,
              builder: (_, _) => const Scaffold(
                body: AutoTabsRouter(
                  routes: [NamedRoute('FirstTab'), NamedRoute('MailTab')],
                ),
              ),
              children: [
                NamedRouteDef(
                  name: 'FirstTab',
                  path: 'first',
                  builder: (_, _) => page('FirstTab'),
                ),
                NamedRouteDef(
                  name: 'MailTab',
                  path: 'mail',
                  builder: (_, _) => const AutoRouter(),
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
                          (resolver, _) =>
                              resolver.route.params.getString('id') == '13'
                              ? resolver.reject()
                              : resolver.next(),
                        ),
                      ],
                      builder: (_, data) =>
                          page('Mail ${data.params.getString('id')}'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();

        await openLink(tester, '/tabs/mail/13');

        expect(tabs.current.name, 'FirstTab');
        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(find.text('Mail 13'), findsNothing);
        expect(router.currentUrl, '/tabs/first');

        await openLink(tester, '/tabs/mail/7');

        expect(tabs.current.name, 'MailTab');
        expect(find.text('Mail 7'), findsOneWidget);
        expect(find.text('Unsaved draft'), findsNothing);
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );
  });
}
