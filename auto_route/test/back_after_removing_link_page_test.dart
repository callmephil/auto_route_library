// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, back() walks the app's own history. A page a platform link
// opened still came back after the app removed it: a link reports its url
// before its pages are in a stack, and when they go in no url is reported,
// so the history never saw the page open and kept its entry as that of a
// page still to come. Its length also counted a page the link closed until
// the next url report, and a link to a page already open left a back()
// that did nothing.
// Found by the review of the batch's history commits (findings 1, 5, 6).
//
// Native behavior this holds to: Flutter's Navigator.removeRoute
// "Immediately remove[s] `route` from the navigator ... and [Route.dispose]
// it" (packages/flutter/lib/src/widgets/navigator.dart 2855-2867, Flutter
// 3.47.9), so no later pop returns to it, however the route was pushed; and
// Navigator.pop takes the top-most present route (navigator.dart 5617, 5652),
// one per call.
//
// Steps: the platform hands the running app a link, the app removes the
// link's page before any other navigation, then back() walks to the first
// page.

RootStackRouter _router() => .build(
  routes: [
    for (final page in ['H', 'A', 'C'])
      NamedRouteDef(
        name: page,
        path: page == 'H' ? '/' : '/${page.toLowerCase()}',
        builder: (_, _) => NamedPage(page),
      ),
    NamedRouteDef(
      name: 'Shell',
      path: '/shell',
      builder: (_, _) => const AutoRouter(),
      children: [
        for (final page in ['X', 'Y'])
          NamedRouteDef(
            name: page,
            path: page == 'X' ? '' : page.toLowerCase(),
            builder: (_, _) => NamedPage(page),
          ),
      ],
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
          children: [
            for (final page in ['OneX', 'OneY'])
              NamedRouteDef(
                name: page,
                path: page == 'OneX' ? '' : 'y',
                builder: (_, _) => NamedPage(page),
              ),
          ],
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

// Opens H, pushes [pages] over it a frame apart, then hands the app [link].
Future<RootStackRouter> _openAtLink(
  WidgetTester tester,
  String link, {
  List<String> pages = const [],
}) async {
  final root = _router();
  await pumpRouterConfigApp(tester, root.config());
  for (final page in pages) {
    unawaited(root.push(NamedRoute(page)));
    await tester.pumpAndSettle();
  }
  await tester.binding.handlePushRoute(link);
  await tester.pumpAndSettle();
  return root;
}

StackRouter _shell(RootStackRouter root) => root.innerRouterOf('Shell')!;

StackRouter _tabStack(RootStackRouter root) =>
    root.innerRouterOf<TabsRouter>('Tabs')!.innerRouterOf('One')!;

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

typedef _Removal = void Function(RootStackRouter root);

// Each removal after a link: the link, the history's length and
// canNavigateBack right after the call, before any frame, and the urls
// back() then shows.
final Map<String, (String, _Removal, (int, bool), List<String>)> _removals = {
  'link /c, then removeLast': (
    '/c',
    (root) => root.removeLast(),
    (1, false),
    ['/'],
  ),
  'link /c, then removeRoute C': (
    '/c',
    (root) {
      final top = root.current;
      root.removeRoute(top);
    },
    (1, false),
    ['/'],
  ),
  'link /c, then removeWhere C': (
    '/c',
    (root) => root.removeWhere((data) => data.name == 'C'),
    (1, false),
    ['/'],
  ),
  'link /c, then navigate to H underneath': (
    '/c',
    (root) => unawaited(root.navigate(const NamedRoute('H'))),
    (1, false),
    ['/'],
  ),
  'link /c, then replaceAll [A]': (
    '/c',
    (root) => unawaited(root.replaceAll(const [NamedRoute('A')])),
    (1, false),
    ['/a'],
  ),
  'link /shell/y, then the shell removeLast': (
    '/shell/y',
    (root) => _shell(root).removeLast(),
    (2, true),
    ['/shell', '/'],
  ),
  'link /tabs/one/y, then the tab removeLast': (
    '/tabs/one/y',
    (root) => _tabStack(root).removeLast(),
    (2, true),
    ['/tabs/one', '/'],
  ),
  'control: link /c, push A, then removeWhere C': (
    '/c',
    (root) {
      unawaited(root.push(const NamedRoute('A')));
      root.removeWhere((data) => data.name == 'C');
    },
    (2, true),
    ['/a', '/'],
  ),
};

void main() {
  for (final MapEntry(key: name, value: (link, removal, atOnce, walk))
      in _removals.entries) {
    testWidgets('$name: back() never opens the removed page', (tester) async {
      final root = await _openAtLink(tester, link);
      removal(root);
      // Right after the call, before any frame: the history counts the
      // pages still open only.
      final now = (
        root.navigationHistory.length,
        root.navigationHistory.canNavigateBack,
      );
      await tester.pumpAndSettle();
      expect(now, atOnce);
      expect(await _walkBack(tester, root), walk);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A link /shell/y on H, A counts H and the link, as the '
      'stack', (tester) async {
    final root = await _openAtLink(tester, '/shell/y', pages: ['A']);
    expect(root.stack.map((page) => page.name), ['H', 'Shell']);
    expect(root.navigationHistory.length, 2);
    expect(await _walkBack(tester, root), ['/shell/y', '/']);
  });

  for (final (name, pages) in [
    ('a page underneath C', ['A', 'C']),
    ('the page on top', ['A']),
  ]) {
    testWidgets('A link to A, $name, leaves a back() that goes to H', (
      tester,
    ) async {
      final root = await _openAtLink(tester, '/a', pages: pages);
      expect(root.stack.map((page) => page.name), ['H', 'A']);
      expect(root.navigationHistory.length, 2);
      expect(await _walkBack(tester, root), ['/a', '/']);
    });
  }
}
