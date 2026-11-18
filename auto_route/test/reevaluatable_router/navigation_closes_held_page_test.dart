import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page that a navigation closed opened again at the next sign-in. Fixes
// callmephil/auto_route_library#12.
// Setup: Home, Account and Mail, whose nested router holds Inbox ('') and
// Message ('message/:id'). Account's guard lets a signed-in user through
// and returns without an answer for the others. Message's guard waits for
// a Completer. The session is the router's reevaluateListenable.
// Steps: the app pushes /mail, then Account, and keeps Account's future.
// It navigates to /mail/message/77: Account stays on top while Message's
// guard decides. The user signs out. Message's guard says yes. The user
// signs in again.
// Was: the yes closed Account, but at the sign-in Account opened again on
// top, and its caller never got a result. Account's guard had let go of
// it, so it was held off the stack, and the step that closes the pages
// over Mail once its nested router lets the navigation in took off only the
// pages on the stack.
// Should: the navigation closes Account for good: the sign-in opens nothing
// and Account's caller gets null at the close. A held page that no
// navigation closed still comes back on its guard's yes.
// Native behavior this holds to: Flutter's Navigator disposes a route that
// it removes "with its future completed" (Navigator.removeRoute,
// navigator.dart, Flutter 3.50.0); a removed route does not come back
// without a new push.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void set({required bool signedIn}) {
    isSignedIn = signedIn;
    notifyListeners();
  }
}

void main() {
  late _Session session;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
  });

  NamedRouteDef page(
    String name,
    String path, {
    AutoRouteGuard? guard,
    List<NamedRouteDef>? children,
  }) => .new(
    name: name,
    path: path,
    guards: [?guard],
    children: children,
    builder: (_, _) => children == null
        ? Scaffold(body: Text(name))
        : const Scaffold(body: AutoRouter()),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('A navigation that closes a held page closes it for good', (
    tester,
  ) async {
    final messageAnswer = Completer<void>();
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          guard: AutoRouteGuard.simple((resolver, _) {
            if (session.isSignedIn) resolver.next();
          }),
        ),
        page(
          'MailRoute',
          '/mail',
          children: [
            page('InboxRoute', ''),
            page(
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
    session.set(signedIn: false);
    await tester.pumpAndSettle();

    messageAnswer.complete();
    await tester.pumpAndSettle();
    final stackAfterYes = names(router);
    final resultsAfterYes = List.of(results);
    session.set(signedIn: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackAfterYes, ['HomeRoute', 'MailRoute']);
    expect(resultsAfterYes, [null]);
    expect(names(router), ['HomeRoute', 'MailRoute']);
    expect(find.text('AccountRoute'), findsNothing);
    expect(results, [null]);
  });
}
