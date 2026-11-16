import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The root's maybePop, right after a call on the nested router on top in
// the same handler, closes that router's top page, as Flutter's
// Navigator.maybePop closes the route its history holds on top.
// Headless test:
// auto_route/test/maybe_pop_over_nested_router_in_one_turn_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('maybe pop over nested router in one turn', () {
    Widget page(String name, [List<Widget> buttons = const []]) => Scaffold(
      body: SafeArea(child: Column(children: [Text(name), ...buttons])),
    );

    // Steps: open Home and the mail shell, and in it a message and its
    // reply form. Tap 'Send and close'. Its handler replaces the reply form
    // with a notice in the shell's router and calls the root's maybePop,
    // with no await between the calls.
    // Was: the notice stayed on top and the message under it was closed.
    // Should: the notice closes and the message shows.
    testWidgets("The root's maybePop closes the nested router's new top", (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('HomeRoute'),
          ),
          NamedRouteDef(
            name: 'MailRoute',
            path: '/mail',
            builder: (_, _) => const AutoRouter(),
            children: [
              for (final (name, path) in [
                ('InboxRoute', ''),
                ('MessageRoute', 'message'),
                ('SentRoute', 'sent'),
              ])
                NamedRouteDef(
                  name: name,
                  path: path,
                  builder: (_, _) => page(name),
                ),
              NamedRouteDef(
                name: 'ReplyRoute',
                path: 'reply',
                builder: (context, _) => page('ReplyRoute', [
                  TextButton(
                    onPressed: () {
                      final mail = context.router;
                      unawaited(mail.replace(const NamedRoute('SentRoute')));
                      unawaited(mail.root.maybePop());
                    },
                    child: const Text('Send and close'),
                  ),
                ]),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.push(const NamedRoute('MailRoute')));
      await tester.pumpAndSettle();
      final mail = router.innerRouterOf<StackRouter>('MailRoute')!;
      for (final name in ['MessageRoute', 'ReplyRoute']) {
        unawaited(mail.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Send and close'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(mail.stack.map((page) => page.name), [
        'InboxRoute',
        'MessageRoute',
      ]);
      expect(find.text('MessageRoute'), findsOneWidget);
      expect(find.text('SentRoute'), findsNothing);
    });
  });
}
