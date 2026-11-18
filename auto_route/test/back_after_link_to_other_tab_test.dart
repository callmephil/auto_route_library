// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Off the web, a link to another tab of the tabs page on screen added three
// entries to the app's history instead of one, so back() went from Feed to
// Settings, then to Feed again and to Settings again before it reached Mail.
// Found by the review of b37bd99a (REVIEW-tabs-nav-2, "found on the way").
//
// Native behavior this holds to: a link is one navigation, and one
// navigation adds one step back. Android's back stack: "Each call
// NavController.navigate() pushes the given destination to the top of the
// stack" and back "pop[s] the top destination off the stack"
// (developer.android.com/guide/navigation/backstack); a bottom navigation
// item navigates with popUpTo the start destination and launchSingleTop
// (developer.android.com/guide/navigation/backstack/multi-back-stacks), so a
// tab never stands twice in a row. Flutter's Navigator.push puts one route
// on and pop takes the top-most one off (packages/flutter/lib/src/widgets/
// navigator.dart 5023 and 5607, Flutter 3.50.0). On iOS a tab change is no
// step back at all. Where the platforms differ, a tab change being one step
// back here is this package's own rule: the order the user went through,
// the latest first, as the app's own navigatePath to the tab already does.
//
// Steps: Home, then the tabs page on Feed; the user picks Mail, then
// Settings; a link to /tabs/feed comes in; walk back to the first page.

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'Home',
      path: '/',
      builder: (_, _) => const NamedPage('Home'),
    ),
    NamedRouteDef(
      name: 'Tabs',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('Feed'),
            NamedRoute<Object?>('Mail'),
            NamedRoute<Object?>('Settings'),
          ],
        ),
      ),
      children: [
        for (final tab in ['Feed', 'Mail', 'Settings'])
          NamedRouteDef(
            name: tab,
            path: tab.toLowerCase(),
            builder: (_, _) => NamedPage(tab),
          ),
      ],
    ),
  ],
);

// Opens the tabs page over Home and picks Mail, then Settings.
Future<RootStackRouter> _openOnSettings(WidgetTester tester) async {
  final root = _router();
  await pumpRouterConfigApp(tester, root.config());
  unawaited(root.push(const NamedRoute('Tabs')));
  await tester.pumpAndSettle();
  final tabs = root.innerRouterOf<TabsRouter>('Tabs')!;
  for (final index in [1, 2]) {
    tabs.setActiveIndex(index);
    await tester.pumpAndSettle();
  }
  return root;
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

const _userWayBack = [
  '/tabs/feed',
  '/tabs/settings',
  '/tabs/mail',
  '/tabs/feed',
  '/',
];

void main() {
  testWidgets('a link to the Feed tab from Settings adds one entry', (
    tester,
  ) async {
    final root = await _openOnSettings(tester);
    expect(root.navigationHistory.length, 4);
    await tester.binding.handlePushRoute('/tabs/feed');
    await tester.pumpAndSettle();
    expectTopPage(root, 'Feed');
    expect(root.navigationHistory.length, 5);
    expect(await _walkBack(tester, root), _userWayBack);
  });

  // The control: the app's own navigatePath to the same tab.
  testWidgets('navigatePath to the Feed tab from Settings adds one entry', (
    tester,
  ) async {
    final root = await _openOnSettings(tester);
    unawaited(root.navigatePath('/tabs/feed'));
    await tester.pumpAndSettle();
    expect(root.navigationHistory.length, 5);
    expect(await _walkBack(tester, root), _userWayBack);
  });

  // A link to the tab on screen shows nothing new: no entry.
  testWidgets('a link to the Settings tab on screen adds no entry', (
    tester,
  ) async {
    final root = await _openOnSettings(tester);
    await tester.binding.handlePushRoute('/tabs/settings');
    await tester.pumpAndSettle();
    expectTopPage(root, 'Settings');
    expect(await _walkBack(tester, root), [
      '/tabs/settings',
      '/tabs/mail',
      '/tabs/feed',
      '/',
    ]);
  });
}
