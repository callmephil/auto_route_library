// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, back() in an AutoRouter.declarative stalled after one step:
// the router hands the step to the app's onNavigate, and the app's list
// rebuilds the router only in the next frame. back() found the page it left
// still on screen when its navigation completed, took the step for refused
// and put that page's entry back; the rebuild then added the page shown as
// a new entry over it. The next back() went to the page left, which the
// app's list no longer held, and nothing moved from then on. With an
// onNavigate that sets the list to the routes it is given, the new page the
// list showed reported while back() ran and got no entry, so back() went
// between the last two pages.
// Found by the batch 3 review of the history (REVIEW-history-2 O3); cause
// traced by the sweep (UNCHECKED-sweep row 11).
//
// Native behavior this holds to: a declarative Navigator's pages are the
// app's list, which the app rebuilds after it is told: "The Navigator widget
// should be rebuilt with a pages list that does not contain the given page
// [...] if the given Page is still present, it will be interpreted as a new
// page to display" (Navigator.onDidRemovePage, packages/flutter/lib/src/
// widgets/navigator.dart 1662-1675, Flutter 3.50.0). So the step is the
// app's rebuild, and a page the app keeps stays, with its way back. Pop
// takes the top-most route only (navigator.dart 5607), and Android's back
// pops the top destination (developer.android.com/guide/navigation/
// backstack), so each back() shows the page before.
//
// Steps: H, then A, then Decl, whose declarative router lists X; the app's
// list grows to X, Y, Z; back() until the history can't, with each way the
// app's onNavigate may change its list.

// How the app's onNavigate changes its list.
enum _Handler {
  // Cuts the list after the last route it is told.
  cutsList,
  // Sets the list to the routes it is told, new pages for them.
  setsList,
  // Keeps its list.
  keepsList,
}

RootStackRouter _router(
  ValueNotifier<List<String>> listed, {
  required _Handler handler,
}) => .build(
  routes: [
    for (final page in ['H', 'A'])
      NamedRouteDef(
        name: page,
        path: page == 'H' ? '/' : '/${page.toLowerCase()}',
        builder: (_, _) => NamedPage(page),
      ),
    NamedRouteDef(
      name: 'Decl',
      path: '/decl',
      builder: (_, _) => ValueListenableBuilder<List<String>>(
        valueListenable: listed,
        builder: (_, pages, _) => AutoRouter.declarative(
          routes: (_) => [for (final page in pages) NamedRoute(page)],
          onNavigate: (routes) {
            final at = listed.value.indexOf(routes.lastOrNull?.name ?? '');
            switch (handler) {
              case .cutsList:
                if (at != -1) listed.value = listed.value.sublist(0, at + 1);
              case .setsList:
                if (routes.isNotEmpty) {
                  listed.value = [for (final route in routes) route.name];
                }
              case .keepsList:
            }
          },
          onPopRoute: (route, _) => listed.value = [
            for (final page in listed.value)
              if (page != route.name) page,
          ],
        ),
      ),
      children: [
        for (final page in ['X', 'Y', 'Z'])
          NamedRouteDef(
            name: page,
            path: page == 'X' ? '' : page.toLowerCase(),
            builder: (_, _) => NamedPage(page),
          ),
      ],
    ),
  ],
);

// Opens H, A, then Decl, and grows its list to X, Y, Z.
Future<RootStackRouter> _openOnZ(
  WidgetTester tester,
  ValueNotifier<List<String>> listed, {
  _Handler handler = .cutsList,
}) async {
  final root = _router(listed, handler: handler);
  await pumpRouterApp(tester, root);
  for (final page in ['A', 'Decl']) {
    unawaited(root.push(NamedRoute(page)));
    await tester.pumpAndSettle();
  }
  listed.value = ['X', 'Y', 'Z'];
  await tester.pumpAndSettle();
  return root;
}

void main() {
  late ValueNotifier<List<String>> listed;
  setUp(() {
    listed = ValueNotifier(['X']);
    addTearDown(listed.dispose);
  });

  testWidgets('back() walks Z, Y, X, A, H', (tester) async {
    final root = await _openOnZ(tester, listed);
    expect(root.navigationHistory.length, 5);
    final walk = [root.currentUrl];
    for (var i = 0; i < 8 && root.navigationHistory.canNavigateBack; i++) {
      root.back();
      await tester.pumpAndSettle();
      walk.add(root.currentUrl);
    }
    expect(walk, ['/decl/z', '/decl/y', '/decl', '/a', '/']);
    expectTopPage(root, 'H');
  });

  testWidgets('each back() takes one step and leaves one entry', (
    tester,
  ) async {
    final root = await _openOnZ(tester, listed);
    root.back();
    await tester.pumpAndSettle();
    expect(listed.value, ['X', 'Y']);
    expect(root.navigationHistory.length, 4);
    root.back();
    await tester.pumpAndSettle();
    expect(listed.value, ['X']);
    expect(root.navigationHistory.length, 3);
  });

  // The app keeps its list: the page stays, and so does its way back.
  testWidgets('back() the app turns down leaves Z and its entry', (
    tester,
  ) async {
    final root = await _openOnZ(tester, listed, handler: .keepsList);
    root.back();
    await tester.pumpAndSettle();
    expect(root.currentUrl, '/decl/z');
    expect(listed.value, ['X', 'Y', 'Z']);
    expect(root.navigationHistory.length, 5);
    expect(root.navigationHistory.canNavigateBack, isTrue);
  });

  // The app's list then holds Y alone: X has left with the app's change, so
  // back() goes from Y to A.
  testWidgets('back() when the app sets its list to the route it is told '
      'walks Z, Y, A, H', (tester) async {
    final root = await _openOnZ(tester, listed, handler: .setsList);
    final walk = [root.currentUrl];
    for (var i = 0; i < 8 && root.navigationHistory.canNavigateBack; i++) {
      root.back();
      await tester.pumpAndSettle();
      walk.add(root.currentUrl);
    }
    expect(walk, ['/decl/z', '/decl/y', '/a', '/']);
  });
}
