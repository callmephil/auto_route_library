// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, back() walks the app's own history, which also holds the
// changes between tabs. The entry a page opened together with the page on
// top gets went after the entry of the nearest page under it, which may be
// older than a change of tabs: after a change to tab Two and back,
// replaceAll([X1, Y1]) in tab One gave the walk Y1, Two, X1, so back()
// showed tab Two between two pages the app had opened together.
// Found by the review of 616a67d8 (finding 4).
//
// Native behavior this holds to: within the tab's stack, Navigator.pop
// takes the top-most route only (packages/flutter/lib/src/widgets/
// navigator.dart 5617 and 5652, Flutter 3.47.9), so Y1 then X1. On iOS a
// tab bar's back never changes tabs; on Android back from another top-level
// tab returns to the start destination (developer.android.com/guide/
// navigation/principles), which is a tab change. Where the platforms differ,
// back not changing tabs here is this package's own rule: the order the user
// went through, the latest first. Pages opened together are opened as the page
// on top is, so their entries go right before its entry.
//
// Steps: in tab One of Tabs over H, change tabs, then open pages together
// in One, and walk back to the first page.

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'H',
      path: '/',
      builder: (_, _) => const NamedPage('H'),
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
            for (final page in ['H1', 'A1', 'B1', 'X1', 'Y1'])
              NamedRouteDef(
                name: page,
                path: page == 'H1' ? '' : page[0].toLowerCase(),
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

// Opens Tabs over H, on tab One.
Future<(RootStackRouter, TabsRouter, StackRouter)> _open(
  WidgetTester tester,
) async {
  final root = _router();
  await pumpRouterConfigApp(tester, root.config());
  unawaited(root.push(const NamedRoute('Tabs')));
  await tester.pumpAndSettle();
  final tabs = root.innerRouterOf<TabsRouter>('Tabs')!;
  return (root, tabs, tabs.innerRouterOf<StackRouter>('One')!);
}

Future<void> _showTab(WidgetTester tester, TabsRouter tabs, int index) async {
  tabs.setActiveIndex(index);
  await tester.pumpAndSettle();
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

void main() {
  testWidgets('replaceAll [X1, Y1] in tab One after a change to Two and '
      'back: back() shows X1 before Two', (tester) async {
    final (root, tabs, one) = await _open(tester);
    await _showTab(tester, tabs, 1);
    await _showTab(tester, tabs, 0);
    unawaited(one.replaceAll(const [NamedRoute('X1'), NamedRoute('Y1')]));
    await tester.pumpAndSettle();
    expect(root.navigationHistory.length, 4);
    expect(await _walkBack(tester, root), [
      '/tabs/one/y',
      '/tabs/one/x',
      '/tabs/two',
      '/',
    ]);
  });

  testWidgets('pushAll [A1, B1] in tab One while Two shows, then back to '
      'One: back() shows A1 before Two', (tester) async {
    final (root, tabs, one) = await _open(tester);
    await _showTab(tester, tabs, 1);
    unawaited(one.pushAll(const [NamedRoute('A1'), NamedRoute('B1')]));
    await tester.pumpAndSettle();
    await _showTab(tester, tabs, 0);
    expect(root.navigationHistory.length, 5);
    expect(await _walkBack(tester, root), [
      '/tabs/one/b',
      '/tabs/one/a',
      '/tabs/two',
      '/tabs/one',
      '/',
    ]);
  });

  testWidgets('control: pushAll [A1, B1] in tab One, then a change to Two: '
      'back() shows Two last', (tester) async {
    final (root, tabs, one) = await _open(tester);
    unawaited(one.pushAll(const [NamedRoute('A1'), NamedRoute('B1')]));
    await tester.pumpAndSettle();
    await _showTab(tester, tabs, 1);
    expect(await _walkBack(tester, root), [
      '/tabs/two',
      '/tabs/one/b',
      '/tabs/one/a',
      '/tabs/one',
      '/',
    ]);
  });
}
