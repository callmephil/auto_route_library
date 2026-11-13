import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guarded page in a nested router was not asked again on sign-out while
// another page covered the page that holds the router, and showed when the
// user went back. Found by the review of the audit's fixes, as an older bug.
// Steps: a shell page at the root holds a nested router with List and, behind
// a guard, Account. Push Account in the shell, then Details at the root, over
// the shell. The session, the router's reevaluateListenable, signs out. Go
// back from Details.
// Was: the guard was not called, and Account showed after the back. A
// reevaluation asked the guards of the root's pages, then went on into the
// nested router of the page on top only.
// Should: every guard is asked again, as the README promises ("re-called on
// all guards"), so Account closes under Details and the back shows List. The
// same holds for a nested router inside a tab of a covered tabs page.
// Flutter's Router parses the whole configuration again when its route
// information changes, not only the part on screen.
void main() {
  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  NamedRouteDef plainRoute(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => page(name),
  );

  // The session, which the guard of Account reads and counts its calls on.
  ({ValueNotifier<bool> isSignedIn, List<String> asked, AutoRouteGuard guard})
  buildSession() {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    final asked = <String>[];
    final guard = AutoRouteGuard.simple((resolver, _) {
      asked.add(resolver.routeName);
      if (isSignedIn.value) {
        resolver.next();
      } else {
        resolver.reject();
      }
    });
    return (isSignedIn: isSignedIn, asked: asked, guard: guard);
  }

  List<NamedRouteDef> shellChildren(AutoRouteGuard guard) => [
    plainRoute('ListRoute', ''),
    plainRoute('AccountRoute', 'account', guards: [guard]),
  ];

  for (final isCovered in [false, true]) {
    final where = isCovered ? 'under another page' : 'on top';
    testWidgets('A sign-out closes the guarded page of a nested router '
        '$where', (tester) async {
      final session = buildSession();
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef.shell(
            name: 'ShellRoute',
            path: '/',
            children: shellChildren(session.guard),
          ),
          plainRoute('DetailsRoute', '/details'),
        ],
      );
      await pumpRouterApp(
        tester,
        router,
        reevaluationNotifier: session.isSignedIn,
      );
      final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;
      unawaited(inner.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      if (isCovered) {
        unawaited(router.push(const NamedRoute('DetailsRoute')));
        await tester.pumpAndSettle();
      }
      session.asked.clear();

      session.isSignedIn.value = false;
      await tester.pumpAndSettle();

      expect(session.asked, ['AccountRoute']);
      expect(inner.stack.map((page) => page.name), ['ListRoute']);

      if (isCovered) {
        unawaited(router.maybePop());
        await tester.pumpAndSettle();
      }

      expect(find.text('ListRoute'), findsOneWidget);
      expect(find.text('AccountRoute'), findsNothing);
    });
  }

  testWidgets('A sign-out closes the guarded page inside a tab of a tabs page '
      'under another page', (tester) async {
    final session = buildSession();
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/',
          builder: (_, _) => const AutoTabsRouter(),
          children: [
            NamedRouteDef.shell(
              name: 'FirstTabRoute',
              path: 'first',
              children: shellChildren(session.guard),
            ),
            plainRoute('SecondTabRoute', 'second'),
          ],
        ),
        plainRoute('DetailsRoute', '/details'),
      ],
    );
    await pumpRouterApp(
      tester,
      router,
      reevaluationNotifier: session.isSignedIn,
    );
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
    final inner = tabs.innerRouterOf<StackRouter>('FirstTabRoute')!;
    unawaited(inner.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    session.asked.clear();

    session.isSignedIn.value = false;
    await tester.pumpAndSettle();

    expect(session.asked, ['AccountRoute']);
    expect(inner.stack.map((page) => page.name), ['ListRoute']);

    unawaited(router.maybePop());
    await tester.pumpAndSettle();

    expect(find.text('ListRoute'), findsOneWidget);
    expect(find.text('AccountRoute'), findsNothing);
  });

  // The nested routers are asked one after another, as a stack asks its own
  // pages: the second guard is asked once the first has answered. Found by
  // the review of this fix, which first asked them side by side, so two
  // guards that send the user to a login page showed two login pages.
  testWidgets('A sign-out that two covered guards answer with a login page '
      'shows one login page', (tester) async {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    final asked = <String>[];
    AutoRouteGuard redirectingGuard(String name) => .simple((resolver, _) {
      asked.add(name);
      if (isSignedIn.value) return resolver.next();
      unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
    });
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef.shell(
          name: 'ShellRoute',
          path: '/',
          children: shellChildren(redirectingGuard('first')),
        ),
        NamedRouteDef.shell(
          name: 'OtherShellRoute',
          path: '/other',
          children: shellChildren(redirectingGuard('second')),
        ),
        plainRoute('DetailsRoute', '/details'),
        plainRoute('LoginRoute', '/login'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;
    unawaited(inner.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(
      router.push(
        const NamedRoute(
          'OtherShellRoute',
          children: [NamedRoute('ListRoute'), NamedRoute('AccountRoute')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    asked.clear();

    isSignedIn.value = false;
    await tester.pumpAndSettle();

    expect(asked, ['first']);
    expect(find.text('LoginRoute'), findsOneWidget);
    expect(
      router.stack.where((page) => page.name == 'LoginRoute'),
      hasLength(1),
    );

    // Signing in asks the guards again: the first lets its page stay, which
    // closes its login page, and the second is asked.
    isSignedIn.value = true;
    await tester.pumpAndSettle();

    expect(asked, ['first', 'first', 'second']);
    expect(find.text('DetailsRoute'), findsOneWidget);
    expect(router.stack.map((page) => page.name), [
      'ShellRoute',
      'OtherShellRoute',
      'DetailsRoute',
    ]);
  });

  // The pages of a covered nested router whose guards let them stay keep
  // their place, and each guard is asked once.
  testWidgets('A reevaluation that keeps the pages of a covered nested router '
      'asks each guard once', (tester) async {
    final session = buildSession();
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef.shell(
          name: 'ShellRoute',
          path: '/',
          children: shellChildren(session.guard),
        ),
        NamedRouteDef.shell(
          name: 'OtherShellRoute',
          path: '/other',
          children: shellChildren(session.guard),
        ),
      ],
    );
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await pumpRouterApp(tester, router, reevaluationNotifier: changes);
    final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;
    unawaited(inner.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(
      router.push(
        const NamedRoute(
          'OtherShellRoute',
          children: [NamedRoute('ListRoute'), NamedRoute('AccountRoute')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final other = router.innerRouterOf<StackRouter>('OtherShellRoute')!;
    session.asked.clear();

    changes.value++;
    await tester.pumpAndSettle();

    expect(session.asked, ['AccountRoute', 'AccountRoute']);
    expect(inner.stack.map((page) => page.name), ['ListRoute', 'AccountRoute']);
    expect(other.stack.map((page) => page.name), ['ListRoute', 'AccountRoute']);
    expect(find.text('AccountRoute'), findsOneWidget);
  });
}
