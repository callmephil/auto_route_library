import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// pushAll, replaceAll, navigate and the path calls added their pages a
// microtask or more after the call, also when no guard made them wait. A
// navigation called right after one of them, with no await between them,
// acted on the stack without those pages: from Home, pushAll([A, B]) then
// push(C) gave [Home, C, A, B], and replaceAll([B]), push(A), replace(C)
// gave [B, A, C].
// Steps, from [Home], each group called one after the other with no await:
// pushAll([A, B]) then push(C) or removeLast(); replaceAll([B]), push(A),
// replace(C); navigate(A) or pushPath('/a') then replace(B).
// Native behavior this holds to: Flutter's Navigator changes its history as
// each call is made, so pushAndRemoveUntil followed by pushReplacement
// replaces the route just pushed. On iOS setViewControllers followed by
// pushViewController ends on the list given with the pushed controller on
// top, and on the web two history calls apply in the order they were made.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const c = NamedRoute('CRoute');

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  Future<RootStackRouter> open(
    WidgetTester tester, {
    List<AutoRouteGuard> guards = const [],
  }) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('ARoute', '/a'),
          ('BRoute', '/b'),
          ('CRoute', '/c'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => NamedPage(name),
          ),
      ],
      guards: guards,
    );
    await pumpRouterConfigApp(tester, router.config());
    return router;
  }

  final afterBatch = {
    'a push right after pushAll lands above its pages': (
      run: (StackRouter router) {
        unawaited(router.pushAll([a, b]));
        unawaited(router.push(c));
      },
      expected: ['HomeRoute', 'ARoute', 'BRoute', 'CRoute'],
    ),
    'removeLast right after pushAll removes its last page': (
      run: (StackRouter router) {
        unawaited(router.pushAll([a, b]));
        router.removeLast();
      },
      expected: ['HomeRoute', 'ARoute'],
    ),
    'a replace right after replaceAll and a push replaces the pushed page': (
      run: (StackRouter router) {
        unawaited(router.replaceAll([b]));
        unawaited(router.push(a));
        unawaited(router.replace(c));
      },
      expected: ['BRoute', 'CRoute'],
    ),
    'a replace right after navigate to a new page replaces that page': (
      run: (StackRouter router) {
        unawaited(router.navigate(a));
        unawaited(router.replace(b));
      },
      expected: ['HomeRoute', 'BRoute'],
    ),
    'a replace right after pushPath replaces the page of the path': (
      run: (StackRouter router) {
        unawaited(router.pushPath('/a'));
        unawaited(router.replace(b));
      },
      expected: ['HomeRoute', 'BRoute'],
    ),
    'pushAll right after a push lands above its page': (
      run: (StackRouter router) {
        unawaited(router.push(c));
        unawaited(router.pushAll([a, b]));
      },
      expected: ['HomeRoute', 'CRoute', 'ARoute', 'BRoute'],
    ),
  };

  for (final MapEntry(key: name, value: calls) in afterBatch.entries) {
    testWidgets('In one turn, $name', (tester) async {
      final router = await open(tester);

      calls.run(router);
      await tester.pumpAndSettle();

      expect(stackNames(router), calls.expected);
      expect(find.text(router.topRoute.name), findsOneWidget);
    });
  }

  // Should: the pages are on the stack as the call returns, as a list of
  // routes is in the Navigator's history as pushAndRemoveUntil returns.
  testWidgets('The pages of replaceAll are on the stack as it returns', (
    tester,
  ) async {
    final router = await open(tester);

    unawaited(router.replaceAll([a, b]));

    expect(stackNames(router), ['ARoute', 'BRoute']);
    expect(router.currentUrl, '/b');

    await tester.pumpAndSettle();

    expect(find.text('BRoute'), findsOneWidget);
  });

  // The same with a guard for every route that answers in its own call, as
  // the usual signed-in check does.
  testWidgets('With a guard that answers at once, a push right after pushAll '
      'lands above its pages', (tester) async {
    final router = await open(
      tester,
      guards: [AutoRouteGuard.simple((resolver, _) => resolver.next())],
    );

    unawaited(router.pushAll([a, b]));
    unawaited(router.push(c));

    expect(stackNames(router), ['HomeRoute', 'ARoute', 'BRoute', 'CRoute']);

    await tester.pumpAndSettle();

    expect(find.text('CRoute'), findsOneWidget);
  });
}
