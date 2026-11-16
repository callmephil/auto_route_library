import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The app's navigate into a page already open keeps the dialog over it when
// a guard of that page's nested router rejects the navigation, and closes it
// once that guard lets it in. navigatePath leaves it open, so a dialog that
// navigates and then pops itself ends on the page it opened.
// Headless test: auto_route/test/guards/navigate_into_open_page_keeps_dialog_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigate into open page keeps dialog', () {
    // Steps: Mail is open on message 42 with a dialog over it. The app
    // navigates to message 13, whose guard rejects it, then to message 14,
    // which its guard lets in. Then a second dialog navigates with
    // navigatePath to 15 and pops itself.
    // Was: navigate closed the dialog on 13.
    // Should: the dialog stays after 13 and closes as 14 opens; the second
    // dialog's own pop ends on 15.
    testWidgets('A navigate a nested guard rejects keeps the dialog', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
          ),
          NamedRouteDef(
            name: 'MailRoute',
            path: '/mail',
            builder: (_, _) => const Scaffold(body: AutoRouter()),
            children: [
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
                builder: (_, data) => SafeArea(
                  child: Center(
                    child: Text('Mail ${data.params.getString('id')}'),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.navigatePath('/mail/42'));
      await tester.pumpAndSettle();
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
      );
      await tester.pumpAndSettle();

      PageRouteInfo<Object?> message(String id) => NamedRoute(
        'MailRoute',
        children: [
          NamedRoute('MessageRoute', params: {'id': id}),
        ],
      );
      unawaited(router.navigate(message('13')));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(find.text('Mail 42'), findsOneWidget);

      unawaited(router.navigate(message('14')));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved draft'), findsNothing);
      expect(find.text('Mail 14'), findsOneWidget);

      // navigatePath leaves the dialog open: its own button navigates and
      // then pops it, in one handler.
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Unsent reply')),
      );
      await tester.pumpAndSettle();
      final reply = tester.element(find.text('Unsent reply'));
      unawaited(router.navigatePath('/mail/15'));
      Navigator.of(reply).pop();
      await tester.pumpAndSettle();
      expect(find.text('Unsent reply'), findsNothing);
      expect(find.text('Mail 15'), findsOneWidget);
    });

    // Steps: the tabs show Mail on message 42 with a dialog over the tabs.
    // The app navigates in that tab to message 13, whose guard rejects it,
    // then to message 14, which its guard lets in.
    // Was: the dialog closed on the navigation to 13.
    // Should: the dialog stays after 13 and closes as 14 opens.
    testWidgets(
      'A navigate a guard in the tab rejects keeps the dialog over the tabs',
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
                  builder: (_, _) => const Text('FirstTab'),
                ),
                NamedRouteDef(
                  name: 'MailTab',
                  path: 'mail',
                  builder: (_, _) => const AutoRouter(),
                  children: [
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
                      builder: (_, data) => SafeArea(
                        child: Center(
                          child: Text('Mail ${data.params.getString('id')}'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.navigatePath('/tabs/mail/42'));
        await tester.pumpAndSettle();
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
        );
        await tester.pumpAndSettle();

        unawaited(router.navigatePath('/tabs/mail/13'));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(find.text('Mail 42'), findsOneWidget);

        unawaited(router.navigatePath('/tabs/mail/14'));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved draft'), findsNothing);
        expect(find.text('Mail 14'), findsOneWidget);
      },
    );
  });
}
