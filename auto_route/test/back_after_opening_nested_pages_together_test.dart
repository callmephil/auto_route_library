// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, back() walks the app's own history. Pages a nested router got
// in the same call that put its page on, as push(N(children: [X, Y, Z])) or
// pushAll([A, N(children: [X, Y])]), shared one entry: the first back()
// closed them all. The nested router is built a frame after the call
// reported its url, and its pages going in reported none, so the history
// never gave the pages under the top their entries.
// Found by the review of 616a67d8 (finding 2).
//
// Native behavior this holds to: Navigator.pop "Pop[s] the top-most route
// off the navigator" (packages/flutter/lib/src/widgets/navigator.dart 5617,
// Flutter 3.47.9), taking only the last present route (5652): one route per
// pop, whether the routes went in alone or together, and the pages of a
// nested navigator before the page that holds it.
//
// Steps: in a stack (the root router's, a shell's nested router's, or a
// tab's router's), the app opens N with its children in one call, then
// back() walks to the first page.

// Where the stack under test lives: the url of its first page and the
// suffix of its route names.
enum _Host {
  root('/', ''),
  shell('/shell', 'Shell'),
  tab('/tabs/one', 'One');

  new(this.prefix, this.suffix);

  final String prefix;
  final String suffix;

  NamedRoute<Object?> route(String page, [List<String>? children]) => .new(
    '$page$suffix',
    children: [
      for (final child in children ?? const <String>[])
        NamedRoute<Object?>('$child$suffix'),
    ],
  );

  // The url of [page], N's pages under N.
  String url(String page) => switch (page) {
    'H' => prefix,
    'X' => url('N'),
    'Y' || 'Z' => '${url('N')}/${page.toLowerCase()}',
    _ when this == root => '/${page.toLowerCase()}',
    _ => '$prefix/${page.toLowerCase()}',
  };
}

List<NamedRouteDef> _pages(String suffix, {required bool isNested}) => [
  for (final page in ['H', 'A'])
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
  NamedRouteDef(
    name: 'N$suffix',
    path: isNested ? 'n' : '/n',
    builder: (_, _) => const AutoRouter(),
    children: [
      for (final page in ['X', 'Y', 'Z'])
        NamedRouteDef(
          name: '$page$suffix',
          path: page == 'X' ? '' : page.toLowerCase(),
          builder: (_, _) => NamedPage('$page$suffix'),
        ),
    ],
  ),
];

RootStackRouter _router() => .build(
  routes: [
    ..._pages('', isNested: false),
    NamedRouteDef(
      name: 'Shell',
      path: '/shell',
      builder: (_, _) => const AutoRouter(),
      children: _pages('Shell', isNested: true),
    ),
    NamedRouteDef(
      name: 'Tabs',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute<Object?>('One'), NamedRoute<Object?>('Two')],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'One',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: _pages('One', isNested: true),
        ),
        NamedRouteDef(
          name: 'Two',
          path: 'two',
          builder: (_, _) => const NamedPage('Two'),
        ),
      ],
    ),
  ],
);

// Opens [host]'s stack on H, and pushes [pages] in it, a frame apart.
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
      unawaited(root.push(const NamedRoute('Shell')));
    case .tab:
      unawaited(root.push(const NamedRoute('Tabs')));
  }
  await tester.pumpAndSettle();
  final stack = switch (host) {
    .root => root,
    .shell => root.innerRouterOf<StackRouter>('Shell')!,
    .tab =>
      root
          .innerRouterOf<TabsRouter>('Tabs')!
          .innerRouterOf<StackRouter>('One')!,
  };
  for (final page in pages) {
    unawaited(stack.push(host.route(page)));
    await tester.pumpAndSettle();
  }
  return (root, stack);
}

// Steps back with [root] until its history can't, and returns the urls
// shown, the current one first.
Future<List<String>> _walkBack(WidgetTester tester, StackRouter root) async {
  final urls = [root.currentUrl];
  for (var i = 0; i < 12 && root.navigationHistory.canNavigateBack; i++) {
    root.back();
    await tester.pumpAndSettle();
    urls.add(root.currentUrl);
  }
  return urls;
}

typedef _Call = void Function(StackRouter stack, _Host host);

// Each call, the pages pushed before it over H, and the pages back() then
// shows in turn, the page on top first.
final Map<String, (_Call, List<String>, List<String>)> _calls = {
  'push N with X, Y, Z on H, A': (
    (stack, host) => unawaited(stack.push(host.route('N', ['X', 'Y', 'Z']))),
    ['A'],
    ['Z', 'Y', 'X', 'A', 'H'],
  ),
  'pushAll [A, N with X, Y] on H': (
    (stack, host) => unawaited(
      stack.pushAll([
        host.route('A'),
        host.route('N', ['X', 'Y']),
      ]),
    ),
    const [],
    ['Y', 'X', 'A', 'H'],
  ),
};

void main() {
  for (final host in _Host.values) {
    group('In the ${host.name} stack,', () {
      for (final MapEntry(key: name, value: (call, before, shown))
          in _calls.entries) {
        testWidgets('$name, then back() closes one page per call', (
          tester,
        ) async {
          final (root, stack) = await _open(tester, host, pages: before);
          call(stack, host);
          await tester.pumpAndSettle();
          expect(
            root.navigationHistory.length,
            shown.length + (host == .root ? 0 : 1),
          );
          expect(await _walkBack(tester, root), [
            for (final page in shown) host.url(page),
            if (host != .root) '/',
          ]);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }
}
