import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A navigation that closes a page held for its guard closes it for good: a
// later sign-in does not open it again, and its caller gets null, as
// Flutter's Navigator disposes a route it removes with its future completed.
// Headless test:
// auto_route/test/reevaluatable_router/navigation_closes_held_page_test.dart
NamedRouteDef _page(
  String name,
  String path, {
  AutoRouteGuard? guard,
  List<NamedRouteDef>? children,
}) => .new(
  name: name,
  path: path,
  guards: [?guard],
  children: children,
  builder: (_, _) => Scaffold(
    body: SafeArea(child: children == null ? Text(name) : const AutoRouter()),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('navigation closes held page', () {
    // Steps: the app opens /mail, then Account, and navigates to
    // /mail/message/77, whose guard waits. The user signs out, Message's
    // guard says yes, and the user signs in again.
    // Was: Account opened again at the sign-in; its caller never got a
    // result.
    // Should: Mail shows its message, Account stays closed, and its caller
    // gets null.
    testWidgets('A sign-in does not open a page the navigation closed', (
      tester,
    ) async {
      final session = ValueNotifier(true);
      addTearDown(session.dispose);
      final messageAnswer = Completer<void>();
      final router = RootStackRouter.build(
        routes: [
          _page('HomeRoute', '/'),
          _page(
            'AccountRoute',
            '/account',
            guard: AutoRouteGuard.simple((resolver, _) {
              if (session.value) resolver.next();
            }),
          ),
          _page(
            'MailRoute',
            '/mail',
            children: [
              _page('InboxRoute', ''),
              _page(
                'MessageRoute',
                'message/:id',
                guard: AutoRouteGuard.simple((resolver, _) async {
                  await messageAnswer.future;
                  resolver.next();
                }),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.pushPath('/mail'));
      await tester.pumpAndSettle();
      final results = <Object?>[];
      unawaited(
        router.push<String>(const NamedRoute('AccountRoute')).then(results.add),
      );
      await tester.pumpAndSettle();
      unawaited(router.navigatePath('/mail/message/77'));
      await tester.pumpAndSettle();
      session.value = false;
      await tester.pumpAndSettle();
      messageAnswer.complete();
      await tester.pumpAndSettle();
      session.value = true;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Mail shows message 77, in its nested router.
      expectTopPage(router, 'MessageRoute');
      expect(router.stack.map((page) => page.routeData.name), [
        'HomeRoute',
        'MailRoute',
      ]);
      expect(find.text('AccountRoute'), findsNothing);
      expect(results, [null]);
      await expectBrowserUrl('/mail/message/77');
    });
  });
}
