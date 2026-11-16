import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// The root's maybePop closed the wrong page of the nested router on top,
// right after a call on that router in the same handler. In a shell on X,
// Y, Z: the shell's replace(W) and pop(), then the root's maybePop(), ended
// on X, Y, where the same calls a frame apart end on X. After the shell's
// push(W), the root's maybePop() closed Z and left W on top.
// The cause: maybePop took its own router's step first (a top page not built
// yet is closed, the route of a page that just left is taken out), then
// went to its navigator. The navigator hands the pop on to the nested
// router's navigator, which knows neither of the nested router's page that
// is not built yet nor of its page that just left, so it closed its own top
// route. maybePopTop and the system back button ask the router on top, and
// were right.
// Steps: open Home and the shell, and Y and Z in the shell, a frame apart.
// Then, with no await between them, a call on the shell's router and the
// root's maybePop().
// Native behavior this holds to: Flutter's Navigator.maybePop closes the
// route its history holds on top, and a route is in the history from the
// call that pushed it and out of it from the call that removed it. A nested
// Navigator that takes the pop through NavigatorPopHandler does the same
// for its own history.
void main() {
  const w = NamedRoute('WRoute');

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  List<NamedRouteDef> pagesNamed(List<(String, String)> pages) => [
    for (final (name, path) in pages)
      NamedRouteDef(name: name, path: path, builder: (_, _) => NamedPage(name)),
  ];

  final innerPages = [
    ('XRoute', ''),
    ('YRoute', 'y'),
    ('ZRoute', 'z'),
    ('WRoute', 'w'),
  ];

  // Opens Home and [host] over it, and Y and Z in the router [innerOf]
  // finds, a frame apart.
  Future<(RootStackRouter, StackRouter)> open(
    WidgetTester tester, {
    PageRouteInfo host = const NamedRoute('ShellRoute'),
    StackRouter? Function(StackRouter)? innerOf,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        ...pagesNamed([('HomeRoute', '/')]),
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/shell',
          builder: (_, _) => const AutoRouter(),
          children: pagesNamed(innerPages),
        ),
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/tabs',
          builder: (_, _) => const AutoTabsRouter(
            routes: [NamedRoute('FeedTab'), NamedRoute('SavedTab')],
          ),
          children: [
            NamedRouteDef(
              name: 'FeedTab',
              path: 'feed',
              builder: (_, _) => const AutoRouter(),
              children: pagesNamed(innerPages),
            ),
            ...pagesNamed([('SavedTab', 'saved')]),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(host));
    await tester.pumpAndSettle();
    final inner =
        (innerOf ?? (root) => root.innerRouterOf<StackRouter>('ShellRoute'))(
          router,
        )!;
    for (final name in ['YRoute', 'ZRoute']) {
      unawaited(inner.push(NamedRoute(name)));
      await tester.pumpAndSettle();
    }
    return (router, inner);
  }

  // What the nested router does first, and what the root's maybePop in the
  // same turn leaves in it.
  final turns = {
    'replace(W) and pop': (
      (StackRouter inner) {
        unawaited(inner.replace(w));
        inner.pop();
      },
      ['XRoute'],
    ),
    'push(W)': (
      (StackRouter inner) => unawaited(inner.push(w)),
      ['XRoute', 'YRoute', 'ZRoute'],
    ),
    'replace(W)': (
      (StackRouter inner) => unawaited(inner.replace(w)),
      ['XRoute', 'YRoute'],
    ),
    'removeLast': ((StackRouter inner) => inner.removeLast(), ['XRoute']),
  };

  for (final MapEntry(key: calls, value: (turn, left)) in turns.entries) {
    testWidgets("In a shell on X, Y, Z: after its $calls, the root's "
        'maybePop in the same turn leaves ${left.join(', ')}', (tester) async {
      final (router, inner) = await open(tester);

      turn(inner);
      final didPop = await router.maybePop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(didPop, isTrue);
      expect(stackNames(inner), left);
      expect(stackNames(router), ['HomeRoute', 'ShellRoute']);
      expect(find.text(left.lastOrNull ?? ''), findsOneWidget);
      expect(find.text('WRoute'), findsNothing);
    });
  }

  testWidgets("In a tab's router on X, Y, Z: after its replace(W) and pop, "
      "the root's maybePop in the same turn leaves X", (tester) async {
    final (router, inner) = await open(
      tester,
      host: const NamedRoute('TabsRoute'),
      innerOf: (root) => root
          .innerRouterOf<TabsRouter>('TabsRoute')
          ?.innerRouterOf<StackRouter>('FeedTab'),
    );

    unawaited(inner.replace(w));
    inner.pop();
    final didPop = await router.maybePop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(didPop, isTrue);
    expect(stackNames(inner), ['XRoute']);
    expect(find.text('XRoute'), findsOneWidget);
  });

  // These asked the router on top already, and stay as they were.
  final fromTop = <String, Future<bool> Function(WidgetTester, StackRouter)>{
    "the root's maybePopTop": (_, router) => router.maybePopTop(),
    'the system back button': (tester, _) => tester.binding.handlePopRoute(),
  };

  for (final MapEntry(key: from, value: pop) in fromTop.entries) {
    testWidgets('In a shell on X, Y, Z: after its replace(W) and pop, '
        '$from in the same turn leaves X', (tester) async {
      final (router, inner) = await open(tester);

      unawaited(inner.replace(w));
      inner.pop();
      final didPop = await pop(tester, router);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(didPop, isTrue);
      expect(stackNames(inner), ['XRoute']);
    });
  }
}
