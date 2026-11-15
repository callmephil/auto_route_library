import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// router.back() called twice in one handler stepped back once. On Home, A,
// B the two calls ended on Home, A, while the same calls a frame apart end
// on Home.
// The cause: the app's own history takes no step back while one is under
// way, and a step back ended a microtask after the router reported the url
// it went to, also when the router reported it inside back() itself. So the
// second call found a step still under way and did nothing.
// Steps: open Home, A, B, a frame apart, then call back() twice, or three
// times on Home, A, B, C, with no await between the calls.
// Native behavior this holds to: in a browser, two calls of history.back()
// in one task go back two entries (run in Chrome 156: on /c over /, /a, /b,
// two calls end on /a). Flutter's Navigator closes two routes for two calls
// of pop in one turn.
// These tests check the app's own history. On the web back() walks the
// browser's history, which the headless test runner does not connect.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const c = NamedRoute('CRoute');

  final isOpen = ValueNotifier(true);
  final asked = <Completer<void>>[];

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  List<NamedRouteDef> pagesNamed(List<(String, String)> pages) => [
    for (final (name, path) in pages)
      NamedRouteDef(name: name, path: path, builder: (_, _) => NamedPage(name)),
  ];

  // Opens Home and pushes [before] over it, a frame apart. A, B and C ask
  // [guard], when one is given.
  Future<RootStackRouter> open(
    WidgetTester tester, {
    List<PageRouteInfo> before = const [a, b],
    AutoRouteGuard? guard,
  }) async {
    final router = RootStackRouter.build(
      routes: [
        ...pagesNamed([('HomeRoute', '/')]),
        for (final (name, path) in [
          ('ARoute', '/a'),
          ('BRoute', '/b'),
          ('CRoute', '/c'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            guards: [?guard],
            builder: (_, _) => NamedPage(name),
          ),
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/shell',
          builder: (_, _) => const AutoRouter(),
          children: pagesNamed([
            ('XRoute', ''),
            ('YRoute', 'y'),
            ('ZRoute', 'z'),
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

  void back(StackRouter router, {required int times}) {
    for (var i = 0; i < times; i++) {
      router.back();
    }
  }

  setUp(() {
    isOpen.value = true;
    asked.clear();
  });

  testWidgets('On Home, A, B, two calls of back in one turn end on Home', (
    tester,
  ) async {
    final router = await open(tester);

    back(router, times: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(router.currentUrl, '/');
    expect(router.navigationHistory.length, 1);
    expect(router.canNavigateBack, isFalse);
  }, skip: kIsWeb);

  testWidgets('On Home, A, B, C, three calls of back in one turn end on Home '
      'and a fourth does nothing', (tester) async {
    final router = await open(tester, before: const [a, b, c]);

    back(router, times: 4);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute']);
    expect(router.navigationHistory.length, 1);
  }, skip: kIsWeb);

  testWidgets('A page pushed in the same turn leaves with the first back, '
      'the page under it with the second', (tester) async {
    final router = await open(tester);
    final results = <Object?>[];

    unawaited(router.push(c).then(results.add));
    back(router, times: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute', 'ARoute']);
    expect(find.text('ARoute'), findsOneWidget);
    expect(results, [null]);
    expect(router.navigationHistory.length, 2);
  }, skip: kIsWeb);

  testWidgets('A page pushed right after two calls of back gets its own '
      'entry', (tester) async {
    final router = await open(tester);

    back(router, times: 2);
    unawaited(router.push(c));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'CRoute']);
    expect(router.navigationHistory.length, 2);

    router.back();
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute']);
  }, skip: kIsWeb);

  testWidgets('In a nested router on X, Y, Z, two calls of back in one turn '
      'end on X', (tester) async {
    final router = await open(tester, before: const [NamedRoute('ShellRoute')]);
    final inner = router.innerRouterOf<StackRouter>('ShellRoute')!;
    for (final name in ['YRoute', 'ZRoute']) {
      unawaited(inner.push(NamedRoute(name)));
      await tester.pumpAndSettle();
    }

    back(router, times: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(inner), ['XRoute']);
    expect(find.text('XRoute'), findsOneWidget);
    expect(router.currentUrl, '/shell');
  }, skip: kIsWeb);

  // back() asks the guard of a page it has to open again: A is pushed, then
  // navigate to Home closes it, which leaves the entries /, /a, /.
  Future<RootStackRouter> openWithClosedPageBehind(
    WidgetTester tester,
    AutoRouteGuard guard,
  ) async {
    final router = await open(tester, before: const [a], guard: guard);
    unawaited(router.navigate(const NamedRoute('HomeRoute')));
    await tester.pumpAndSettle();
    expect(router.navigationHistory.length, 3);
    return router;
  }

  testWidgets('When the guard of the page gone back to answers in its own '
      'call, the second back of the turn steps on', (tester) async {
    final router = await openWithClosedPageBehind(
      tester,
      AutoRouteGuard.simple((resolver, _) => resolver.next()),
    );

    back(router, times: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute']);
    expect(router.navigationHistory.length, 1);
  }, skip: kIsWeb);

  // A step back that waits on a guard is still under way, so a second call
  // does nothing, in one turn as a frame apart.
  testWidgets('While the guard of the page gone back to decides, a second '
      'back does nothing', (tester) async {
    final router = await openWithClosedPageBehind(
      tester,
      AutoRouteGuard.simple((resolver, _) async {
        if (isOpen.value) return resolver.next();
        final answer = Completer<void>();
        asked.add(answer);
        await answer.future;
        resolver.next();
      }),
    );
    isOpen.value = false;

    back(router, times: 2);
    await tester.pumpAndSettle();
    final whileAsked = stackNames(router);
    for (final answer in asked) {
      answer.complete();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(asked, hasLength(1));
    expect(whileAsked, ['HomeRoute']);
    expect(stackNames(router), ['HomeRoute', 'ARoute']);
    expect(router.navigationHistory.length, 2);
  }, skip: kIsWeb);
}
