import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The app's own navigation to a page in another tab, opened before, shows
// that tab only once the guards of its nested router let the navigation in.
// Headless test:
// auto_route/test/nested_tabs_router/app_tab_change_waits_for_nested_guards_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('app tab change waits for nested guards', () {
    // Steps: Mail was opened before; the app shows FirstTab with a dialog
    // open. It navigates to message 13 in Mail, whose guard rejects it,
    // then to message 14, which its guard lets in.
    // Was: Mail showed and the dialog closed on 13.
    // Should: FirstTab and the dialog stay after 13; 14 shows Mail and
    // closes the dialog. Then from FirstTab to message 88, whose guard shows
    // Mail's own sign-in page and waits: Mail shows with it, and the message
    // once signed in.
    testWidgets(
      'A tab change its nested guard rejects keeps the tab and the dialog',
      (tester) async {
        Widget page(String name) => SafeArea(child: Center(child: Text(name)));
        final signedIn = Completer<bool>();
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
                      name: 'MailLoginRoute',
                      path: 'login',
                      builder: (_, _) => page('MailLoginRoute'),
                    ),
                    NamedRouteDef(
                      name: 'MessageRoute',
                      path: ':id',
                      guards: [
                        AutoRouteGuard.simple((resolver, mail) async {
                          switch (resolver.route.params.getString('id')) {
                            case '13':
                              return resolver.reject();
                            case '88':
                              unawaited(
                                mail.push(const NamedRoute('MailLoginRoute')),
                              );
                              final isSignedIn = await signedIn.future;
                              mail.removeWhere(
                                (data) => data.name == 'MailLoginRoute',
                              );
                              return isSignedIn
                                  ? resolver.next()
                                  : resolver.reject();
                          }
                          resolver.next();
                        }),
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
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
          ..setActiveIndex(1);
        await tester.pumpAndSettle();
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();

        unawaited(router.navigatePath('/tabs/mail/13'));
        await tester.pumpAndSettle();

        expect(tabs.current.name, 'FirstTab');
        expect(find.text('Unsaved draft'), findsOneWidget);

        unawaited(router.navigatePath('/tabs/mail/14'));
        await tester.pumpAndSettle();

        expect(tabs.current.name, 'MailTab');
        expect(find.text('Mail 14'), findsOneWidget);
        expect(find.text('Unsaved draft'), findsNothing);

        // A guard that shows Mail's own sign-in page: the tab shows with it.
        tabs.setActiveIndex(0);
        await tester.pumpAndSettle();
        unawaited(router.navigatePath('/tabs/mail/88'));
        await tester.pumpAndSettle();
        expect(find.text('MailLoginRoute').hitTestable(), findsOneWidget);

        signedIn.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Mail 88'), findsOneWidget);
      },
    );
  });
}
