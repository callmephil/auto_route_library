import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// callmephil/auto_route_library#6: a nested guard's "no" takes back a new
// page that holds tabs, or that builds its nested router in a
// DeferredWidget, as it takes back a page with a plain nested router.
// Native behavior this holds to: on the web a canceled navigation leaves the
// document and its url on screen (HTML standard). Android's conditional
// navigation pops back from a destination whose check fails.
// Headless test:
// auto_route/test/guards/rejected_nested_guard_takes_tabs_or_deferred_page_back_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => Scaffold(
    body: SafeArea(child: Center(child: Text(name))),
  );

  group('rejected nested guard takes tabs or deferred page back', () {
    // Steps: push A over Home. navigatePath to '/tabmail/message', a tab
    // whose guard says no.
    // Was: TabMail stayed on its Inbox tab at '/tabmail/inbox', over A.
    // Should: Home and A, at '/a'.
    testWidgets('A tab guard saying no keeps Home and A', (tester) async {
      final answer = Completer<bool>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('Home'),
          ),
          NamedRouteDef(
            name: 'ARoute',
            path: '/a',
            builder: (_, _) => page('A'),
          ),
          NamedRouteDef(
            name: 'TabMailRoute',
            path: '/tabmail',
            builder: (_, _) => const Scaffold(
              body: AutoTabsRouter(
                routes: [NamedRoute('InboxTab'), NamedRoute('MessageTab')],
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'InboxTab',
                path: 'inbox',
                builder: (_, _) => page('InboxTab'),
              ),
              NamedRouteDef(
                name: 'MessageTab',
                path: 'message',
                guards: [
                  AutoRouteGuard.simple(
                    (resolver, _) async => await answer.future
                        ? resolver.next()
                        : resolver.reject(),
                  ),
                ],
                builder: (_, _) => page('MessageTab'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('ARoute')));
      await tester.pumpAndSettle();
      final failures = <NavigationFailure>[];

      unawaited(
        router.navigatePath('/tabmail/message', onFailure: failures.add),
      );
      await tester.pumpAndSettle();
      answer.complete(false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ARoute']);
      expect(find.text('A'), findsOneWidget);
      expect(router.currentUrl, '/a');
      expect(failures, hasLength(1));
      await expectBrowserUrl('/a');
    });

    // Steps: open a dialog over Home. navigatePath to '/mail/77'; Mail
    // builds its nested router once its deferred library loads, and the
    // guard of message 77 says no.
    // Was: Mail stayed on its inbox at '/mail', and the dialog closed.
    // Should: Home and its dialog, at '/'.
    testWidgets('A deferred page guard saying no keeps Home and its dialog', (
      tester,
    ) async {
      final library = Completer<void>();
      final answer = Completer<bool>();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('Home'),
          ),
          NamedRouteDef(
            name: 'MailRoute',
            path: '/mail',
            builder: (_, _) => DeferredWidget(
              () => library.future,
              () => const Scaffold(body: AutoRouter()),
            ),
            children: [
              NamedRouteDef(
                name: 'InboxRoute',
                path: '',
                builder: (_, _) => page('Inbox'),
              ),
              NamedRouteDef(
                name: 'MessageRoute',
                path: ':id',
                guards: [
                  AutoRouteGuard.simple(
                    (resolver, _) async => await answer.future
                        ? resolver.next()
                        : resolver.reject(),
                  ),
                ],
                builder: (_, _) => page('Message'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Draft')),
      );
      await tester.pumpAndSettle();

      unawaited(router.navigatePath('/mail/77'));
      // The placeholder spins while the library loads.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      library.complete();
      await tester.pumpAndSettle();
      answer.complete(false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('Draft'), findsOneWidget);
      expect(router.currentUrl, '/');
      await expectBrowserUrl('/');
    });
  });
}
