import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A page the app closed came back on screen. On Home, A, B, a replace to C
// and two pops, with no await between them, ended on Home, A, with A on
// screen. The same calls a frame apart end on Home.
// The cause: the page a replace takes off keeps its route in the navigator
// until the navigator is rebuilt. The first pop closed C, which had no route
// yet. The second went to Navigator.pop, which closed the navigator's top
// route, the one of B, a page already gone, and A stayed open. removeLast,
// removeWhere and pushAndPopUntil leave such a route too, and maybePop,
// popTop and popAndPush hand their pop to the navigator the same way, in a
// nested router and in a tab's router as well. A pop after navigate to an
// open page was right before, and is here so it stays right.
// Steps: open Home, A, B, a frame apart. Then make a call that takes B off
// the stack and the pops each test names, with no await between them.
// Native behavior this holds to: Flutter's Navigator no longer counts a
// route as present from the call that replaced or removed it. So after
// Navigator.pushReplacement to C on Home, A, B, a pop closes C and the next
// pop closes A, and the Navigator ends on Home.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const c = NamedRoute('CRoute');
  const d = NamedRoute('DRoute');

  final popRefusals = <bool>[];

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
    popRefusals.clear();
    final router = RootStackRouter.build(
      routes: [
        ...pagesNamed([
          ('HomeRoute', '/'),
          ('ARoute', '/a'),
          ('BRoute', '/b'),
          ('CRoute', '/c'),
          ('DRoute', '/d'),
        ]),
        NamedRouteDef(
          name: 'KeptRoute',
          path: '/kept',
          builder: (_, _) => PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) => popRefusals.add(!didPop),
            child: const NamedPage('KeptRoute'),
          ),
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
              children: pagesNamed([
                ('XRoute', ''),
                ('YRoute', 'y'),
                ('ZRoute', 'z'),
                ('WRoute', 'w'),
              ]),
            ),
            ...pagesNamed([('SavedTab', 'saved')]),
          ],
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

  void pop(StackRouter router, {required int times}) {
    for (var i = 0; i < times; i++) {
      router.pop();
    }
  }

  // Each takes B off the stack and pops, in one turn, down to Home, with
  // the page it names on top.
  final turns = {
    'replace(C), pop, pop': (
      (StackRouter router) {
        unawaited(router.replace(c));
        pop(router, times: 2);
      },
      'HomeRoute',
    ),
    'replace(C), maybePop, maybePop': (
      (StackRouter router) {
        unawaited(router.replace(c));
        unawaited(router.maybePop());
        unawaited(router.maybePop());
      },
      'HomeRoute',
    ),
    'replace(C), pop, popTop': (
      (StackRouter router) {
        unawaited(router.replace(c));
        router
          ..pop()
          ..popTop();
      },
      'HomeRoute',
    ),
    'replace(C), pop, popAndPush(D)': (
      (StackRouter router) {
        unawaited(router.replace(c));
        router.pop();
        unawaited(router.popAndPush(d));
      },
      'DRoute',
    ),
    'replace(C), replace(D), pop, pop': (
      (StackRouter router) {
        unawaited(router.replace(c));
        unawaited(router.replace(d));
        pop(router, times: 2);
      },
      'HomeRoute',
    ),
    'removeLast, pop': (
      (StackRouter router) => router
        ..removeLast()
        ..pop(),
      'HomeRoute',
    ),
    'removeLast, maybePop': (
      (StackRouter router) {
        router.removeLast();
        unawaited(router.maybePop());
      },
      'HomeRoute',
    ),
    'removeWhere(B), pop': (
      (StackRouter router) => router
        ..removeWhere((route) => route.name == 'BRoute')
        ..pop(),
      'HomeRoute',
    ),
    'navigate(A), pop': (
      (StackRouter router) {
        unawaited(router.navigate(a));
        router.pop();
      },
      'HomeRoute',
    ),
    'pushAndPopUntil(D, until A), pop, pop': (
      (StackRouter router) {
        unawaited(
          router.pushAndPopUntil(d, predicate: ModalRoute.withName('ARoute')),
        );
        pop(router, times: 2);
      },
      'HomeRoute',
    ),
  };

  for (final MapEntry(key: calls, value: (turn, top)) in turns.entries) {
    final isHome = top == 'HomeRoute';
    testWidgets('On Home, A, B: $calls in one turn end on '
        '${isHome ? 'Home' : 'Home, D'}', (tester) async {
      final router = await open(tester);

      turn(router);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(router), ['HomeRoute', if (!isHome) top]);
      expect(find.text(top), findsOneWidget);
      expect(find.text('ARoute'), findsNothing);
      expect(router.currentUrl, isHome ? '/' : '/d');
    });
  }

  testWidgets('The page a replace opened answers its caller as the first pop '
      'closes it, and the page under the replaced one closes with the '
      'second', (tester) async {
    final router = await open(tester);
    final results = <String?>[];

    unawaited(router.replace<String>(c).then(results.add));
    router.pop('closed');
    final afterFirst = stackNames(router);
    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(afterFirst, ['HomeRoute', 'ARoute']);
    expect(results, ['closed']);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    for (final closed in ['ARoute', 'BRoute', 'CRoute']) {
      expect(find.text(closed), findsNothing);
    }
  });

  testWidgets('A maybePop after a replace and a pop asks the PopScope of the '
      'page then on top, not the replaced page', (tester) async {
    final router = await open(
      tester,
      before: const [NamedRoute('KeptRoute'), b],
    );

    unawaited(router.replace(c));
    router.pop();
    final didHandle = await router.maybePop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(didHandle, isTrue);
    expect(popRefusals, [true]);
    expect(stackNames(router), ['HomeRoute', 'KeptRoute']);
    expect(find.text('KeptRoute'), findsOneWidget);
  });

  testWidgets('A dialog over the replaced page leaves with it, and the pops '
      'close the pages of the stack', (tester) async {
    final router = await open(tester);
    showDialog<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const Text('Dialog'),
    );
    await tester.pumpAndSettle();

    unawaited(router.replace(c));
    pop(router, times: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('Dialog'), findsNothing);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  final nested = <String, (PageRouteInfo, StackRouter? Function(StackRouter))>{
    'a nested router': (
      const NamedRoute('ShellRoute'),
      (router) => router.innerRouterOf<StackRouter>('ShellRoute'),
    ),
    "a tab's router": (
      const NamedRoute('TabsRoute'),
      (router) => router
          .innerRouterOf<TabsRouter>('TabsRoute')
          ?.innerRouterOf<StackRouter>('FeedTab'),
    ),
  };

  for (final MapEntry(key: where, value: (host, innerOf)) in nested.entries) {
    testWidgets('In $where on X, Y, Z: replace(W), pop, pop in one turn end '
        'on X', (tester) async {
      final router = await open(tester, before: [host]);
      final inner = innerOf(router)!;
      for (final name in ['YRoute', 'ZRoute']) {
        unawaited(inner.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      unawaited(inner.replace(const NamedRoute('WRoute')));
      pop(inner, times: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(inner), ['XRoute']);
      expect(find.text('XRoute'), findsOneWidget);
      expect(find.text('YRoute'), findsNothing);
    });
  }
}
