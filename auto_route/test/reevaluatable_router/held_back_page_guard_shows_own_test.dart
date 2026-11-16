import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Neighbors of the page held back while its guard, asked again, decides
// (held_back_page_leaves_screen_test.dart, Phil's decision 4): a guard that
// shows something of its own on screen and returns without awaiting it, and
// a page of a nested router.
// Setup: Home and Account; Account's guard lets a signed-in user through.
// Signed out, it shows a "Sign in again?" dialog, or pushes a sign-in page,
// and returns, answering from what the user does there. The session is the
// router's reevaluateListenable.
// Should: the guard waits on the user, on screen, so its page stays under
// what it shows, as a page under the guard's redirect does: had the page
// left, Flutter would close the dialog over it, and the guard would hear
// that as a cancel. A page of a nested router whose guard returns without
// an answer leaves that router's stack and the screen, and comes back on a
// yes, as a root page does.
// Native behavior this holds to: an alert on iOS (UIAlertController) or
// Android (AlertDialog) stays over the screen that showed it until the user
// answers; Flutter's Navigator removes the pageless routes over a page that
// leaves its pages.
void main() {
  late ValueNotifier<bool> isSignedIn;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
  });

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Shows the dialog without awaiting it, and answers from its buttons.
  final dialogGuard = AutoRouteGuard.simple((resolver, router) {
    if (isSignedIn.value) return resolver.next();
    unawaited(
      showDialog<bool>(
        context: router.root.navigatorKey.currentContext!,
        builder: (dialog) => AlertDialog(
          title: const Text('Sign in again?'),
          actions: [
            for (final (label, isYes) in [('Sign in', true), ('Cancel', false)])
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(isYes),
                child: Text(label),
              ),
          ],
        ),
      ).then((isYes) => (isYes ?? false) ? resolver.next() : resolver.reject()),
    );
  });

  for (final isYes in [true, false]) {
    testWidgets('A guard asked again that shows a dialog and returns keeps '
        'its page under the dialog; the user taps '
        '${isYes ? 'Sign in' : 'Cancel'}', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('AccountRoute', '/account', guard: dialogGuard),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final answers = <String?>[];
      unawaited(
        router.push<String>(const NamedRoute('AccountRoute')).then(answers.add),
      );
      await tester.pumpAndSettle();

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      final whileAsking = (
        names(router).join(' '),
        find.text('AccountRoute').evaluate().length,
        find.text('Sign in again?').evaluate().length,
      );
      await tester.tap(find.text(isYes ? 'Sign in' : 'Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(whileAsking, ('HomeRoute AccountRoute', 1, 1));
      expect(find.text('Sign in again?'), findsNothing);
      expect(names(router), ['HomeRoute', if (isYes) 'AccountRoute']);
      expect(find.text(isYes ? 'AccountRoute' : 'HomeRoute'), findsOneWidget);
      expect(answers, isYes ? isEmpty : [null]);
    });
  }

  testWidgets('A guard asked again that pushes a sign-in page and returns '
      'keeps its page under the sign-in page', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          guard: AutoRouteGuard.simple((resolver, guarded) {
            if (isSignedIn.value) return resolver.next();
            unawaited(
              guarded
                  .push<bool>(const NamedRoute('SignInRoute'))
                  .then(
                    (isIn) =>
                        (isIn ?? false) ? resolver.next() : resolver.reject(),
                  ),
            );
          }),
        ),
        page('SignInRoute', '/sign-in'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    final whileSigningIn = names(router);
    unawaited(router.maybePop(true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(whileSigningIn, ['HomeRoute', 'AccountRoute', 'SignInRoute']);
    expect(names(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
  });

  for (final isYes in [true, false]) {
    testWidgets('A page of a nested router whose guard, asked again, returns '
        'without an answer leaves the screen; then the guard says '
        '${isYes ? 'yes' : 'no'}', (tester) async {
      void Function({required bool isYes})? answer;
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef.shell(
            name: 'MailRoute',
            path: '/',
            children: [
              page('InboxRoute', ''),
              page(
                'MessageRoute',
                'message',
                guard: AutoRouteGuard.simple((resolver, _) {
                  if (isSignedIn.value) return resolver.next();
                  answer = ({required isYes}) =>
                      isYes ? resolver.next() : resolver.reject();
                }),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final mail = router.innerRouterOf<StackRouter>('MailRoute')!;
      final answers = <String?>[];
      unawaited(
        mail.push<String>(const NamedRoute('MessageRoute')).then(answers.add),
      );
      await tester.pumpAndSettle();

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      final whileAsked = (
        names(mail).join(' '),
        find.text('MessageRoute').evaluate().length,
        router.urlState.url,
      );
      answer?.call(isYes: isYes);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(whileAsked, ('InboxRoute', 0, '/'));
      expect(names(mail), ['InboxRoute', if (isYes) 'MessageRoute']);
      expect(find.text(isYes ? 'MessageRoute' : 'InboxRoute'), findsOneWidget);
      expect(router.urlState.url, isYes ? '/message' : '/');
      expect(answers, isYes ? isEmpty : [null]);
    });
  }
}
