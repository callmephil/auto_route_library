import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page was lost when the app rebuilt while its guard, asked again, had
// not answered yet. A lead of the audit of auto_route/lib; on dev too.
// Setup: Home, and Account behind a guard that lets a signed-in user through
// and otherwise returns without an answer and answers later from a callback,
// as one that asks the session to sign the user in again does. The session
// is the router's reevaluateListenable. Code awaits the result of
// push(AccountRoute()).
// Steps: on Account, the session ends. The guard is asked again and returns
// without an answer, so its page is held back, off the stack, until it
// answers. Meanwhile the app rebuilds its pages, as any navigation or url
// update makes it do. The user signs in again and the guard lets the page
// stay.
// Was: Account was gone for good and Home stayed on screen, and the code
// that opened Account had been told it closed, with null. As the navigator
// got the pages without Account it closed Account's route the way it closes
// a popped one, and the router took that for a pop by the user.
// Should: Account is back once its guard lets it stay, and the code that
// opened it still waits and gets the result it closes with later. Flutter's
// Navigator completes a route's popped future when the route leaves for
// good, and a page that is given to it again gets a route again.
void main() {
  late ValueNotifier<bool> isSignedIn;
  late List<NavigationResolver> asking;
  late List<String?> answers;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    asking = [];
    answers = [];
  });

  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(
      appBar: AppBar(leading: const AutoLeadingButton()),
      body: Text(name),
    ),
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home and Account, with Bills over it when [hasBills], then ends
  // the session: Account's guard is asked again and returns without an
  // answer.
  Future<RootStackRouter> signOutOnAccount(
    WidgetTester tester, {
    bool hasBills = false,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          AutoRouteGuard.simple((resolver, _) {
            if (isSignedIn.value) return resolver.next();
            asking.add(resolver);
          }),
        ),
        page('BillsRoute', '/bills'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    unawaited(
      router.push<String>(const NamedRoute('AccountRoute')).then(answers.add),
    );
    await tester.pumpAndSettle();
    if (hasBills) {
      unawaited(router.push(const NamedRoute('BillsRoute')));
      await tester.pumpAndSettle();
    }
    isSignedIn.value = false;
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute']);
    return router;
  }

  for (final hasBills in [false, true]) {
    final pages = hasBills ? 'pages' : 'page';
    testWidgets('The $pages held back for a guard that answers later are '
        'back after a rebuild, with the caller still waiting', (tester) async {
      final router = await signOutOnAccount(tester, hasBills: hasBills);

      router.notifyAll();
      await tester.pumpAndSettle();
      final onScreenAfterRebuild = find.text('HomeRoute').evaluate().length;
      final answersAfterRebuild = answers.length;
      asking.singleOrNull?.next();
      await tester.pumpAndSettle();
      final back = stackNames(router);
      if (hasBills) {
        router.pop();
        await tester.pumpAndSettle();
      }
      final answersBeforeClose = List.of(answers);
      unawaited(router.maybePop('saved'));
      await tester.pumpAndSettle();

      expect((onScreenAfterRebuild, answersAfterRebuild), (1, 0));
      expect(back, ['HomeRoute', 'AccountRoute', if (hasBills) 'BillsRoute']);
      expect(answersBeforeClose, isEmpty);
      expect(stackNames(router), ['HomeRoute']);
      expect(answers, ['saved']);
    });
  }

  testWidgets('A page held back for a guard that then rejects is closed '
      'after a rebuild, and its caller gets null', (tester) async {
    final router = await signOutOnAccount(tester);

    router.notifyAll();
    await tester.pumpAndSettle();
    asking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(answers, [null]);
  });

  // Since Phil's decision 4 of 2026-11-16 the held-back page leaves the
  // screen at once, without a rebuild, so the user can no longer close it
  // meanwhile; held_back_page_leaves_screen_test.dart tests what a pop then
  // does.
  testWidgets('A page held back for a guard that answers later leaves the '
      'screen before any rebuild, with the caller still waiting', (
    tester,
  ) async {
    final router = await signOutOnAccount(tester);

    final whileHeld = (
      find.text('HomeRoute').evaluate().length,
      find.text('AccountRoute').evaluate().length,
      answers.length,
    );
    asking.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(whileHeld, (1, 0, 0));
    expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
    expect(answers, isEmpty);
  });
}
