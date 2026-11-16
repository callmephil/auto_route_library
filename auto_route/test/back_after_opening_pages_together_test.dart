// Off the web only: on the web, back() is the browser's own back step, and
// the browser history gives these pages their entries itself.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, the router's back() walks the app's own history. Pages the
// app opened together, with pushAll or a replaceAll of several pages, got
// one entry, that of the page on top: back() from it closed them all at
// once (pushAll), or did nothing although pages were still under it
// (replaceAll).
//
// Native behavior this holds to: Flutter's Navigator closes one route per
// pop, whether the routes were pushed alone or together; the web's entry
// list gives each page the app opened together its own entry. Pages one link
// opened together share the link's entry there, as the web's list does: the
// user made one navigation, and back() leaves it as one.
//
// Steps: open H in a stack (the root router's, a shell's nested router's, or
// a tab's router's), make the call, then call back(), a frame later or in
// the same turn, and walk back to the first page.

// Where the stack under test lives: the url of its first page and the
// suffix of its route names.
enum _Host {
  root('/', ''),
  shell('/shell', 'Shell'),
  tab('/tabs/one', 'One');

  new(this.prefix, this.suffix);

  final String prefix;
  final String suffix;

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

// Opens [host]'s stack on H, then pushes [pages] in it, a frame apart, and
// returns the root router and that stack's router.
Future<(RootStackRouter, StackRouter)> _open(
  WidgetTester tester,
  _Host host, {
  List<String> pages = const [],
}) async {
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
  final stack = _stackOf(root, host)!;
  for (final page in pages) {
    unawaited(stack.push(NamedRoute(host.routeName(page))));
    await tester.pumpAndSettle();
  }
  return (root, stack);
}

StackRouter? _stackOf(RootStackRouter root, _Host host) => switch (host) {
  .root => root,
  .shell => root.innerRouterOf('ShellRoute'),
  .tab => root.innerRouterOf<TabsRouter>('TabsRoute')?.innerRouterOf('OneTab'),
};

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

// Each call, the pages pushed before it over H, and the pages it leaves.
final Map<String, (_Call, List<String>, List<String>)> _calls = {
  'pushAll [A, B, C] on H': (
    (stack, host) => unawaited(
      stack.pushAll([
        for (final page in ['A', 'B', 'C']) NamedRoute(host.routeName(page)),
      ]),
    ),
    const [],
    ['H', 'A', 'B', 'C'],
  ),
  'replaceAll [B, C] on H, A': (
    (stack, host) => unawaited(
      stack.replaceAll([
        for (final page in ['B', 'C']) NamedRoute(host.routeName(page)),
      ]),
    ),
    ['A'],
    ['B', 'C'],
  ),
  'replaceAll [H, B, C] on H, A': (
    (stack, host) => unawaited(
      stack.replaceAll([
        for (final page in ['H', 'B', 'C']) NamedRoute(host.routeName(page)),
      ]),
    ),
    ['A'],
    ['H', 'B', 'C'],
  ),
};

void main() {
  for (final host in _Host.values) {
    group('In the ${host.name} stack,', () {
      for (final MapEntry(key: name, value: (call, before, left))
          in _calls.entries) {
        testWidgets('$name, then back() a frame later closes one page per '
            'call', (tester) async {
          final (root, stack) = await _open(tester, host, pages: before);
          call(stack, host);
          await tester.pumpAndSettle();
          expect(_names(stack, host), left);
          expect(
            root.navigationHistory.length,
            left.length + (host == .root ? 0 : 1),
          );
          expect(await _walkBack(tester, root), host.walk(left));
          expect(tester.takeException(), isNull);
        });

        testWidgets('$name and back() in one turn closes the page on top', (
          tester,
        ) async {
          final (root, stack) = await _open(tester, host, pages: before);
          call(stack, host);
          root.back();
          await tester.pumpAndSettle();
          final shown = left.sublist(0, left.length - 1);
          expect(_names(stack, host), shown);
          expect(await _walkBack(tester, root), host.walk(shown));
          expect(tester.takeException(), isNull);
        });
      }

      if (host != .root) {
        // A link that opens the stack's router with B over H: both share the
        // link's entry, so back() leaves them as one, as on the web.
        testWidgets('a link that brings H and B shares one entry', (
          tester,
        ) async {
          final root = _router();
          await pumpRouterConfigApp(tester, root.config());
          await tester.binding.handlePushRoute(host.url('B'));
          await tester.pumpAndSettle();
          expect(_names(_stackOf(root, host)!, host), ['H', 'B']);
          expect(root.navigationHistory.length, 2);
          expect(await _walkBack(tester, root), [host.url('B'), '/']);
        });

        // The app's push of a page over the link's pages gets its own entry,
        // and back() from it goes to the link's.
        testWidgets('a push over a link that brings H and B gets its own '
            'entry', (tester) async {
          final root = _router();
          await pumpRouterConfigApp(tester, root.config());
          await tester.binding.handlePushRoute(host.url('B'));
          await tester.pumpAndSettle();
          unawaited(
            _stackOf(root, host)!.push(NamedRoute(host.routeName('C'))),
          );
          await tester.pumpAndSettle();
          expect(root.navigationHistory.length, 3);
          expect(await _walkBack(tester, root), [
            host.url('C'),
            host.url('B'),
            '/',
          ]);
        });

        // B, whose entry H shares, leaves from under C: H takes the entry
        // over, so back() from C still reaches H, as on the web.
        testWidgets('a link that brings H and B, a push of C, then B removed '
            'from under C', (tester) async {
          final root = _router();
          await pumpRouterConfigApp(tester, root.config());
          await tester.binding.handlePushRoute(host.url('B'));
          await tester.pumpAndSettle();
          final stack = _stackOf(root, host)!;
          unawaited(stack.push(NamedRoute(host.routeName('C'))));
          await tester.pumpAndSettle();
          stack.removeWhere((data) => data.name == host.routeName('B'));
          await tester.pumpAndSettle();
          expect(_names(stack, host), ['H', 'C']);
          expect(root.navigationHistory.length, 3);
          expect(await _walkBack(tester, root), host.walk(['H', 'C']));
        });
      }
    });
  }
}
