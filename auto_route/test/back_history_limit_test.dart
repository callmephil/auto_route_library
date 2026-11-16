// Off the web only: on the web, the browser keeps its own history.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, the app's own history keeps at most 21 entries, the oldest
// going first (NavigationHistoryImpl, "limit history registration to 20
// entries"). Since pages opened together get an entry each, pushAll of 25
// pages left 26 entries, and in a tab, pages the limit had dropped got their
// entries again after a change to another tab and back: 25 pushes, then a
// tab change and back, took the history from 21 to 28.
// Found by the review of 616a67d8 (finding 3).
//
// Native behavior this holds to: none; the limit is the history's own, and
// back() still closes one page per call within it, as Navigator.pop takes
// the top-most route only (packages/flutter/lib/src/widgets/navigator.dart
// 5617 and 5652, Flutter 3.47.9).
//
// Steps: open 25 pages in one call or one by one, in the root router or a
// tab's router, change tabs and back where there are tabs, and read the
// history's length; then walk back.

const _count = 25;
const _limit = 21;

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
  testWidgets('pushAll of 25 pages keeps at most 21 entries, and back() '
      'closes one page per call', (tester) async {
    final root = _router();
    await pumpRouterConfigApp(tester, root.config());
    unawaited(
      root.pushAll([for (var i = 1; i <= _count; i++) NamedRoute('P$i')]),
    );
    await tester.pumpAndSettle();
    expect(root.navigationHistory.length, _limit);
    final closed = await _closedPerBack(tester, root, root);
    expect(closed, List.filled(_limit - 1, 1));
  });

  for (final isTogether in [false, true]) {
    final opening = isTogether ? 'pushAll of 25 pages' : '25 pushes';
    testWidgets('$opening in a tab, then a change to the other tab and back, '
        'keeps at most 21 entries', (tester) async {
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
      final lengths = [root.navigationHistory.length];
      for (final index in [1, 0]) {
        tabs.setActiveIndex(index);
        await tester.pumpAndSettle();
        lengths.add(root.navigationHistory.length);
      }
      expect(lengths, everyElement(lessThanOrEqualTo(_limit)));
      expect(lengths.lastOrNull, _limit);
    });
  }
}
