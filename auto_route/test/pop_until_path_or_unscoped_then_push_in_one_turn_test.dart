import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A push called right after popUntilRouteWithPath, or after popUntil or
// popUntilRouteWithName with scoped set to false, was lost when pages had
// been pushed earlier in the same handler. From Home, a push of A, a push
// of B, popUntilRouteWithPath to A and a push of D, with no await between
// them, ended on Home, A: D was gone. A frame apart they end on Home, A, D.
// The cause: the navigator has no route yet for a page pushed in the same
// turn, so these pops waited for the frame that builds it. By then the page
// pushed after the pop was on the stack too, and was closed with the
// others. popUntilRoot and the scoped popUntil and popUntilRouteWithName
// already close such pages in the call, these three did not.
// Steps, from Home, called one after the other with no await: pages pushed
// with push, then one of the pops, then a push of D.
// Native behavior this holds to: Flutter's Navigator changes its history as
// each call is made, so Navigator.push, popUntil and push again in one turn
// end on the route pushed last, over the route popUntil stopped at.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const d = NamedRoute('DRoute');

  final slowGuards = <Completer<void>>[];

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  List<NamedRouteDef> pagesNamed(List<(String, String)> pages) => [
    for (final (name, path) in pages)
      NamedRouteDef(name: name, path: path, builder: (_, _) => NamedPage(name)),
  ];

  // Opens Home and pushes [before] over it, a frame apart.
  Future<RootStackRouter> open(
    WidgetTester tester, {
    List<PageRouteInfo> before = const [],
  }) async {
    slowGuards.clear();
    final router = RootStackRouter.build(
      routes: [
        ...pagesNamed([('HomeRoute', '/'), ('ARoute', '/a'), ('DRoute', '/d')]),
        NamedRouteDef(
          name: 'BRoute',
          path: '/b',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.next())],
          builder: (_, _) => const NamedPage('BRoute'),
        ),
        NamedRouteDef(
          name: 'SlowRoute',
          path: '/slow',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              final answer = Completer<void>();
              slowGuards.add(answer);
              await answer.future;
              resolver.next();
            }),
          ],
          builder: (_, _) => const NamedPage('SlowRoute'),
        ),
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/shell',
          builder: (_, _) => const AutoRouter(),
          children: pagesNamed([
            ('XRoute', ''),
            ('YRoute', 'y'),
            ('ZRoute', 'z'),
            ('WRoute', 'w'),
          ]),
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

  bool isNamedA(Route<Object?> route) => route.settings.name == 'ARoute';

  // Each pops down to A, or to Home, the first page.
  final pops = {
    'popUntilRouteWithPath(/a)': (
      (StackRouter router) => router.popUntilRouteWithPath('/a'),
      'ARoute',
    ),
    'popUntilRouteWithPath(/)': (
      (StackRouter router) => router.popUntilRouteWithPath('/'),
      'HomeRoute',
    ),
    'popUntilRouteWithPath of no page': (
      (StackRouter router) => router.popUntilRouteWithPath('/nowhere'),
      'HomeRoute',
    ),
    'popUntilRouteWithPath(/a, scoped: false)': (
      (StackRouter router) => router.popUntilRouteWithPath('/a', scoped: false),
      'ARoute',
    ),
    'popUntilRouteWithName(A, scoped: false)': (
      (StackRouter router) =>
          router.popUntilRouteWithName('ARoute', scoped: false),
      'ARoute',
    ),
    'popUntil(named A, scoped: false)': (
      (StackRouter router) => router.popUntil(isNamedA, scoped: false),
      'ARoute',
    ),
    'popUntil(with ModalRoute.withName(A), scoped: false)': (
      (StackRouter router) =>
          router.popUntil(ModalRoute.withName('ARoute'), scoped: false),
      'ARoute',
    ),
    'popUntil(first, scoped: false)': (
      (StackRouter router) =>
          router.popUntil((route) => route.isFirst, scoped: false),
      'HomeRoute',
    ),
  };

  for (final MapEntry(key: call, value: (popUntil, reached)) in pops.entries) {
    final left = ['HomeRoute', if (reached == 'ARoute') 'ARoute'];
    testWidgets('After a push of A and of B, $call and a push in one turn '
        'end on the pushed page over ${left.join(', ')}', (tester) async {
      final router = await open(tester);

      unawaited(router.push(a));
      unawaited(router.push(b));
      popUntil(router);
      final afterPop = stackNames(router);
      unawaited(router.push(d));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(afterPop, left);
      expect(stackNames(router), [...left, 'DRoute']);
      expect(find.text('DRoute'), findsOneWidget);
      expect(router.currentUrl, '/d');
    });
  }

  testWidgets('A page on screen and one pushed in the same turn both close '
      'for popUntilRouteWithPath, and a page pushed after it stays', (
    tester,
  ) async {
    final router = await open(tester, before: const [a]);

    unawaited(router.push(b));
    router.popUntilRouteWithPath('/');
    unawaited(router.push(d));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute', 'DRoute']);
    expect(find.text('DRoute'), findsOneWidget);
  });

  testWidgets('A pop that is not scoped stops at a page pushed in the same '
      'turn in the nested router on top', (tester) async {
    final router = await open(tester, before: const [NamedRoute('ShellRoute')]);
    final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;

    unawaited(inner.push(const NamedRoute('YRoute')));
    unawaited(inner.push(const NamedRoute('ZRoute')));
    router.popUntil((route) => route.settings.name == 'YRoute', scoped: false);
    unawaited(inner.push(const NamedRoute('WRoute')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(inner), ['XRoute', 'YRoute', 'WRoute']);
    expect(stackNames(router), ['HomeRoute', 'ShellRoute']);
    expect(find.text('WRoute'), findsOneWidget);
  });

  // A page pushed at the root covers the shell, so the pop walks the root
  // alone, in one turn as a frame apart, and never asks about the shell's
  // own pages.
  testWidgets('A pop that is not scoped, over a page pushed in the same '
      'turn at the root, closes the shell under it as a frame apart', (
    tester,
  ) async {
    final router = await open(tester, before: const [NamedRoute('ShellRoute')]);
    final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;

    unawaited(inner.push(const NamedRoute('YRoute')));
    unawaited(router.push(a));
    router.popUntil((route) => route.isFirst, scoped: false);
    unawaited(router.push(d));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute', 'DRoute']);
    expect(find.text('DRoute'), findsOneWidget);
  });

  // A page whose guard still decides is not on the stack, so the pop does
  // not wait for it, and it opens once its guard answers.
  testWidgets('A page whose guard answers later opens over the page '
      'popUntilRouteWithPath stopped at', (tester) async {
    final router = await open(tester);

    unawaited(router.push(a));
    unawaited(router.push(const NamedRoute('SlowRoute')));
    router.popUntilRouteWithPath('/');
    await tester.pumpAndSettle();
    final whileAsked = stackNames(router);
    for (final answer in slowGuards) {
      answer.complete();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(whileAsked, ['HomeRoute']);
    expect(stackNames(router), ['HomeRoute', 'SlowRoute']);
  });
}
