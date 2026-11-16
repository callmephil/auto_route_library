// Off the web only: on the web, back() is the browser's own back step, and
// the browser history drops a removed page's entry itself.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, the router's back() walks the app's own history. A page the
// app takes off a stack without a pop, with removeLast, removeRoute,
// removeWhere, removeUntil, replaceAll or navigate to a page underneath, used
// to keep its entry there, and the call even added one for the page left on
// top: back() then opened the removed page again, as after a sign-in that
// ends in replaceAll, which showed the replaced sign-in page again.
//
// Native behavior this holds to: a route taken out with Flutter's
// Navigator.removeRoute is disposed and never comes back with a later pop
// (navigator.dart, removeRoute); an Android activity that was finished is
// "popped from the top of the stack and destroyed" and is no longer in the
// back stack ("Tasks and the back stack"); a view controller left out of
// UIKit's setViewControllers(_:animated:) is gone from the navigation stack.
// So after any of these calls the history holds the entries of the pages
// still open, in order, and back() goes to the page under the top.
//
// Steps: open H, A and B in a stack (the root router's, a shell's nested
// router's, or a tab's router's), make the call, then call back(), a frame
// later or in the same turn, and walk back to the first page.

// Where the stack under test lives: the url of its first page and the
// suffix of its route names.
enum _Host {
  root('/', ''),
  shell('/shell', 'Shell'),
  tab('/tabs/one', 'One');

  new(this.prefix, this.suffix);

  final String prefix;
  final String suffix;
  // The number of history entries before the entry of the stack's first
  // page: the root's Home, under a nested stack.
  int get entriesBefore => this == root ? 0 : 1;

  String routeName(String page) => '$page$suffix';

  String url(String page) => switch (page) {
    'H' => prefix,
    _ when this == root => '/${page.toLowerCase()}',
    _ => '$prefix/${page.toLowerCase()}',
  };

  // The urls back() shows from [pages], the stack of this host, the page on
  // top first, to the app's first page.
  List<String> walk(List<String> pages) => [
    for (final page in pages.reversed) url(page),
    if (this != root) '/',
  ];
}

Completer<bool>? _waitingGuard;

// Lets C in at once, unless a test holds it with [_waitingGuard].
final _guard = AutoRouteGuard.simple((resolver, _) async {
  final waiting = _waitingGuard;
  if (waiting == null) return resolver.next();
  final isLetIn = await waiting.future;
  return isLetIn ? resolver.next() : resolver.reject();
});

List<NamedRouteDef> _pages(String suffix, {required bool isNested}) => [
  for (final page in ['H', 'A', 'B', 'C'])
    NamedRouteDef(
      name: '$page$suffix',
      path: switch ((page, isNested)) {
        ('H', true) => '',
        ('H', false) => '/',
        (_, true) => page.toLowerCase(),
        (_, false) => '/${page.toLowerCase()}',
      },
      guards: [if (page == 'C') _guard],
      builder: (_, _) => NamedPage('$page$suffix'),
    ),
];

RootStackRouter _router() => .build(
  routes: [
    ..._pages('', isNested: false),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell',
      builder: (_, _) => const AutoRouter(),
      children: _pages('Shell', isNested: true),
    ),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('OneTab'),
            NamedRoute<Object?>('TwoTab'),
          ],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'OneTab',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: _pages('One', isNested: true),
        ),
        NamedRouteDef(
          name: 'TwoTab',
          path: 'two',
          builder: (_, _) => const NamedPage('TwoTab'),
        ),
      ],
    ),
  ],
);

// Opens H, A and B in [host]'s stack, and returns the root router and that
// stack's router.
Future<(RootStackRouter, StackRouter)> _openHAB(
  WidgetTester tester,
  _Host host,
) async {
  final root = _router();
  await pumpRouterConfigApp(tester, root.config());
  switch (host) {
    case .root:
      break;
    case .shell:
      unawaited(root.push(const NamedRoute('ShellRoute')));
    case .tab:
      unawaited(root.push(const NamedRoute('TabsRoute')));
  }
  await tester.pumpAndSettle();
  final stack = switch (host) {
    .root => root,
    .shell => root.innerRouterOf<StackRouter>('ShellRoute')!,
    .tab =>
      root
          .innerRouterOf<TabsRouter>('TabsRoute')!
          .innerRouterOf<StackRouter>('OneTab')!,
  };
  for (final page in ['A', 'B']) {
    unawaited(stack.push(NamedRoute(host.routeName(page))));
    await tester.pumpAndSettle();
  }
  return (root, stack);
}

// The names on [stack], without the host's suffix.
List<String> _names(StackRouter stack, _Host host) => [
  for (final page in stack.stack)
    page.routeData.name.substring(
      0,
      page.routeData.name.length - host.suffix.length,
    ),
];

// Steps back with [root] until its history can't, and returns the urls
// shown, the current one first.
Future<List<String>> _walkBack(WidgetTester tester, StackRouter root) async {
  final urls = [root.currentUrl];
  for (var i = 0; i < 10 && root.navigationHistory.canNavigateBack; i++) {
    root.back();
    await tester.pumpAndSettle();
    urls.add(root.currentUrl);
  }
  return urls;
}

typedef _Call = void Function(StackRouter stack, _Host host);

bool _isPage(RouteData<Object?> data, _Host host, String page) =>
    data.name == host.routeName(page);

bool _isRoute(Route<Object?> route, _Host host, String page) =>
    route.settings.name == host.routeName(page);

// Each call on H, A, B, and the pages it leaves.
final Map<String, (_Call, List<String>)> _calls = {
  'removeLast': ((stack, _) => stack.removeLast(), ['H', 'A']),
  'removeRoute B': (
    (stack, _) {
      final top = stack.current;
      stack.removeRoute(top);
    },
    ['H', 'A'],
  ),
  'removeWhere B': (
    (stack, host) => stack.removeWhere((data) => _isPage(data, host, 'B')),
    ['H', 'A'],
  ),
  'removeWhere A, under the top': (
    (stack, host) => stack.removeWhere((data) => _isPage(data, host, 'A')),
    ['H', 'B'],
  ),
  'removeUntil A': (
    (stack, host) => stack.removeUntil((data) => _isPage(data, host, 'A')),
    ['H', 'A'],
  ),
  'replaceAll [H, C]': (
    (stack, host) => unawaited(
      stack.replaceAll([
        NamedRoute(host.routeName('H')),
        NamedRoute(host.routeName('C')),
      ]),
    ),
    ['H', 'C'],
  ),
  'navigate A, a page underneath': (
    (stack, host) => unawaited(stack.navigate(NamedRoute(host.routeName('A')))),
    ['H', 'A'],
  ),
  'control: pop': ((stack, _) => stack.pop(), ['H', 'A']),
  'control: popUntil A': (
    (stack, host) => stack.popUntil((route) => _isRoute(route, host, 'A')),
    ['H', 'A'],
  ),
  'control: pushAndPopUntil C until H': (
    (stack, host) => unawaited(
      stack.pushAndPopUntil(
        NamedRoute(host.routeName('C')),
        predicate: (route) => _isRoute(route, host, 'H'),
      ),
    ),
    ['H', 'C'],
  ),
};

void main() {
  setUp(() => _waitingGuard = null);

  for (final host in _Host.values) {
    group('In the ${host.name} stack on H, A, B,', () {
      for (final MapEntry(key: name, value: (call, left)) in _calls.entries) {
        testWidgets('$name, then a frame later back()', (tester) async {
          final (root, stack) = await _openHAB(tester, host);
          call(stack, host);
          await tester.pumpAndSettle();
          final history = root.navigationHistory;
          expect(_names(stack, host), left);
          expect(history.length, host.entriesBefore + left.length);
          expect(history.canNavigateBack, isTrue);
          root.back();
          await tester.pumpAndSettle();
          expect(_names(stack, host), left.sublist(0, left.length - 1));
          expect(await _walkBack(tester, root), host.walk(['H']));
          expect(history.length, 1);
          expect(tester.takeException(), isNull);
        });

        testWidgets('$name and back() in one turn', (tester) async {
          final (root, stack) = await _openHAB(tester, host);
          call(stack, host);
          root.back();
          await tester.pumpAndSettle();
          expect(_names(stack, host), left.sublist(0, left.length - 1));
          expect(await _walkBack(tester, root), host.walk(['H']));
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('removeLast, then a push of C', (tester) async {
        final (root, stack) = await _openHAB(tester, host);
        stack.removeLast();
        await tester.pumpAndSettle();
        unawaited(stack.push(NamedRoute(host.routeName('C'))));
        await tester.pumpAndSettle();
        expect(_names(stack, host), ['H', 'A', 'C']);
        expect(root.navigationHistory.length, host.entriesBefore + 3);
        expect(await _walkBack(tester, root), host.walk(['H', 'A', 'C']));
      });

      testWidgets('removeLast while the guard of a pushed C waits', (
        tester,
      ) async {
        final (root, stack) = await _openHAB(tester, host);
        final waiting = _waitingGuard = Completer<bool>();
        unawaited(stack.push(NamedRoute(host.routeName('C'))));
        await tester.pumpAndSettle();
        stack.removeLast();
        await tester.pumpAndSettle();
        expect(_names(stack, host), ['H', 'A']);
        expect(root.navigationHistory.length, host.entriesBefore + 2);
        waiting.complete(true);
        await tester.pumpAndSettle();
        _waitingGuard = null;
        expect(_names(stack, host), ['H', 'A', 'C']);
        expect(root.navigationHistory.length, host.entriesBefore + 3);
        expect(await _walkBack(tester, root), host.walk(['H', 'A', 'C']));
      });
    });
  }
}
