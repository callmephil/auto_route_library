// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// router.back() opened a page the app had closed. On Home, A, B, a push of
// C and a pop in one handler close C before it is ever built. A back() after
// that, in the same handler or later, put C on screen again. With a replace
// in place of the push, as in replace(C), pop(), back(), the stack ended on
// Home, A, C, though C's caller had its answer.
// The cause: a page gets its entry in the app's own history as it is
// pushed. A page the navigator has built is popped by the navigator, which
// reports the pop, and the history drops the page's entry. A page closed
// before it was built is taken off the stack by the router alone, which
// rebuilt the url as after any change: the closed page kept its entry, and
// the page then on top got a new one after it.
// Steps: open Home, A, B, a frame apart. In one handler push or replace
// with C and pop, or push pages and call popUntilRoot. Then call back().
// Native behavior this holds to: a closed screen is not in the back stack.
// On Android an activity that finishes leaves the task's back stack, so
// back never returns to it. In a browser a document left by history.back()
// is no entry behind the current one. Flutter's Navigator.pop takes the
// route out of the history for good.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const c = NamedRoute('CRoute');
  const d = NamedRoute('DRoute');

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  List<NamedRouteDef> pagesNamed(List<(String, String)> pages) => [
    for (final (name, path) in pages)
      NamedRouteDef(name: name, path: path, builder: (_, _) => NamedPage(name)),
  ];

  // Opens Home and pushes [before] over it, a frame apart.
  Future<RootStackRouter> open(
    WidgetTester tester, {
    List<PageRouteInfo> before = const [a, b],
  }) async {
    final router = RootStackRouter.build(
      routes: [
        ...pagesNamed([
          ('HomeRoute', '/'),
          ('ARoute', '/a'),
          ('BRoute', '/b'),
          ('DRoute', '/d'),
        ]),
        NamedRouteDef(
          name: 'CRoute',
          path: '/c',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.next())],
          builder: (_, _) => const NamedPage('CRoute'),
        ),
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/shell',
          builder: (_, _) => const AutoRouter(),
          children: pagesNamed([('XRoute', ''), ('YRoute', 'y')]),
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    for (final route in before) {
      unawaited(router.push(route));
      await tester.pumpAndSettle();
    }
    return router;
  }

  // The history's length, the names on the stack and the url.
  (int, String, String) shown(StackRouter router) => (
    router.navigationHistory.length,
    stackNames(router).join(' '),
    router.currentUrl,
  );

  // Each closes a page before it is built, in one turn. Then, a frame
  // later: what the history holds, and where a back() ends.
  final turns = {
    'push(C), pop': (
      (StackRouter router) {
        unawaited(router.push(c));
        router.pop();
      },
      (3, 'HomeRoute ARoute BRoute', '/b'),
      (2, 'HomeRoute ARoute', '/a'),
    ),
    'push(C), maybePop': (
      (StackRouter router) {
        unawaited(router.push(c));
        unawaited(router.maybePop());
      },
      (3, 'HomeRoute ARoute BRoute', '/b'),
      (2, 'HomeRoute ARoute', '/a'),
    ),
    'replace(C), pop': (
      (StackRouter router) {
        unawaited(router.replace(c));
        router.pop();
      },
      (2, 'HomeRoute ARoute', '/a'),
      (1, 'HomeRoute', '/'),
    ),
    'push(C), push(D), popUntilRoot': (
      (StackRouter router) {
        unawaited(router.push(c));
        unawaited(router.push(d));
        router.popUntilRoot();
      },
      (1, 'HomeRoute', '/'),
      (1, 'HomeRoute', '/'),
    ),
    'push(C), popUntilRoot, push(D)': (
      (StackRouter router) {
        unawaited(router.push(c));
        router.popUntilRoot();
        unawaited(router.push(d));
      },
      (2, 'HomeRoute DRoute', '/d'),
      (1, 'HomeRoute', '/'),
    ),
  };

  for (final MapEntry(key: calls, value: (turn, after, afterBack))
      in turns.entries) {
    testWidgets('On Home, A, B: after $calls in one turn, back opens no '
        'closed page', (tester) async {
      final router = await open(tester);

      turn(router);
      await tester.pumpAndSettle();
      final afterTurn = shown(router);
      router.back();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect((afterTurn, shown(router)), (after, afterBack));
      expect(find.text('CRoute'), findsNothing);
    });
  }

  testWidgets('On Home, A, B: replace(C), pop and back in one turn end on '
      'Home', (tester) async {
    final router = await open(tester);
    final results = <Object?>[];

    unawaited(router.replace(c).then(results.add));
    router
      ..pop()
      ..back();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shown(router), (1, 'HomeRoute', '/'));
    expect(results, [null]);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(find.text('CRoute'), findsNothing);
  });

  testWidgets('In a nested router: after a push and a pop in one turn, back '
      'leaves the shell', (tester) async {
    final router = await open(tester, before: const [NamedRoute('ShellRoute')]);
    final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;

    unawaited(inner.push(const NamedRoute('YRoute')));
    inner.pop();
    await tester.pumpAndSettle();
    final afterTurn = shown(router);
    router.back();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (afterTurn, shown(router)),
      ((2, 'HomeRoute ShellRoute', '/shell'), (1, 'HomeRoute', '/')),
    );
    expect(find.text('YRoute'), findsNothing);
  });

  testWidgets('A shell pushed and popped in one turn leaves no entry of its '
      'own or of its first page', (tester) async {
    final router = await open(tester);

    unawaited(router.push(const NamedRoute('ShellRoute')));
    router.pop();
    await tester.pumpAndSettle();
    final afterTurn = shown(router);
    router.back();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (afterTurn, shown(router)),
      ((3, 'HomeRoute ARoute BRoute', '/b'), (2, 'HomeRoute ARoute', '/a')),
    );
    expect(find.text('XRoute'), findsNothing);
  });
}
