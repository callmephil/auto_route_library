// Off the web only: on the web, the browser keeps its own history.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, the app's own history keeps one entry for each open page and
// no more, and no limit drops the entry of an open page (issue
// callmephil/auto_route_library#17). Since pages opened together get an
// entry each, pushAll of 25 pages leaves 26 entries, and in a tab, a change
// to another tab and back adds one entry for each change, not one for each
// page the tab holds.
//
// Native behavior this holds to: Flutter's Navigator keeps every route until
// it is popped, and Android's back stack and iOS's UINavigationController
// have no fixed length (packages/flutter/lib/src/widgets/navigator.dart,
// Flutter 3.50.0). back() closes one page per call, as Navigator.pop takes
// the top-most route only.
//
// Steps: open 25 pages in one call or one by one, in the root router or a
// tab's router, change tabs and back where there are tabs, and read the
// history's length; then walk back.

const _count = 25;

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'H',
      path: '/',
      builder: (_, _) => const NamedPage('H'),
    ),
    for (var i = 1; i <= _count; i++)
      NamedRouteDef(
        name: 'P$i',
        path: '/p$i',
        builder: (_, _) => NamedPage('P$i'),
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
            NamedRouteDef(
              name: 'H1',
              path: '',
              builder: (_, _) => const NamedPage('H1'),
            ),
            for (var i = 1; i <= _count; i++)
              NamedRouteDef(
                name: 'Q$i',
                path: 'q$i',
                builder: (_, _) => NamedPage('Q$i'),
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

// Steps back with [root] until its history can't, and returns how many
// pages of [stack] each step closed.
Future<List<int>> _closedPerBack(
  WidgetTester tester,
  StackRouter root,
  StackRouter stack,
) async {
  final closed = <int>[];
  for (var i = 0; i < 40 && root.navigationHistory.canNavigateBack; i++) {
    final before = stack.stack.length;
    root.back();
    await tester.pumpAndSettle();
    closed.add(before - stack.stack.length);
  }
  return closed;
}

void main() {
  testWidgets('pushAll of 25 pages keeps an entry for each page, and back() '
      'closes one page per call', (tester) async {
    final root = _router();
    await pumpRouterConfigApp(tester, root.config());
    unawaited(
      root.pushAll([for (var i = 1; i <= _count; i++) NamedRoute('P$i')]),
    );
    await tester.pumpAndSettle();
    expect(root.navigationHistory.length, _count + 1);
    final closed = await _closedPerBack(tester, root, root);
    expect(closed, List.filled(_count, 1));
  });

  for (final isTogether in [false, true]) {
    final opening = isTogether ? 'pushAll of 25 pages' : '25 pushes';
    testWidgets('$opening in a tab, then a change to the other tab and back, '
        'adds one entry per change', (tester) async {
      final root = _router();
      await pumpRouterConfigApp(tester, root.config());
      unawaited(root.push(const NamedRoute('Tabs')));
      await tester.pumpAndSettle();
      final tabs = root.innerRouterOf<TabsRouter>('Tabs')!;
      final one = tabs.innerRouterOf<StackRouter>('One')!;
      if (isTogether) {
        unawaited(
          one.pushAll([for (var i = 1; i <= _count; i++) NamedRoute('Q$i')]),
        );
        await tester.pumpAndSettle();
      } else {
        for (var i = 1; i <= _count; i++) {
          unawaited(one.push(NamedRoute('Q$i')));
          await tester.pumpAndSettle();
        }
      }
      final opened = root.navigationHistory.length;
      final lengths = [opened];
      for (final index in [1, 0]) {
        tabs.setActiveIndex(index);
        await tester.pumpAndSettle();
        lengths.add(root.navigationHistory.length);
      }
      // Each tab change is one navigation: one entry, not an entry for each
      // page the tab holds.
      expect(lengths, [opened, opened + 1, opened + 2]);
    });
  }
}
