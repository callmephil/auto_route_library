import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// While a slow guard inside a shell that was not open decides, the shell
// shows its placeholder. The shell goes in first and its router asks the
// guard with its own context, as Phil decided for nested guards. A yes
// shows the guarded page. A no takes the shell back.
// Setup: Home at the root path. Mail is a shell with a placeholder that
// reads Loading. It holds Inbox as its first page and Message by id, whose
// guard waits for the test.
// Steps: the app calls navigatePath to message 20, which names Message
// alone for the router of the shell. Then the guard says yes or no.
// Native behavior this holds to: Android's conditional navigation shows the
// destination first and runs its check there, popping back when it fails.
// Flutter's Navigator shows the pages its list holds, and the shell shows
// its own placeholder while it holds none.
void main() {
  for (final isLetIn in [true, false]) {
    testWidgets('The shell shows its placeholder while the guard decides, '
        'then ${isLetIn ? 'the page' : 'Home'}', (tester) async {
      final answer = Completer<bool>();
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
            builder: (_, _) => Scaffold(
              body: AutoRouter(placeholder: (_) => const Text('Loading')),
            ),
            children: [
              NamedRouteDef(
                name: 'InboxRoute',
                path: '',
                builder: (_, _) => const Text('Inbox'),
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
                builder: (_, _) => const Text('Message'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      unawaited(router.navigatePath('/mail/20'));
      await tester.pumpAndSettle();

      expect(find.text('Loading'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);

      answer.complete(isLetIn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      if (isLetIn) {
        expect(find.text('Message'), findsOneWidget);
        expect(router.currentUrl, '/mail/20');
      } else {
        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(router.currentUrl, '/');
      }
      expect(find.text('Loading'), findsNothing);
    });
  }
}
