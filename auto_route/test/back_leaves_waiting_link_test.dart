// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';
import 'utils/held_guard.dart';

// Off the web, back() while the guard of a link still decides leaves the
// link: the guard's answer then changes nothing (callmephil/auto_route_library#32).
//
// Steps: on Home, open Tabs on tab One, or open A. The platform hands the app
// a link to tab Two, or to Detail, whose guard waits. While the guard
// decides, call back(). Then the guard says yes, or no.
// Was: back() took the link's entry as its step and dropped it, and the page
// on screen stayed, but nothing called the link off. After the yes, the
// link's page showed anyway. Detail showed with one entry left in the
// history, so back() could not leave it. Tab Two showed at /tabs/two once
// the link waited for the tab's guard (callmephil/auto_route_library#31).
// Before that fix, the link's entry was gone early, and back() closed the
// tabs page.
// Should: back() leaves the link, and the page on screen stays: One, or A.
// The guard's later answer, yes or no, changes nothing, and back() then goes
// on from that page.
//
// Native behavior this holds to: Android's back finishes the activity a link
// started, and it does not come back; in the HTML standard, a traversal
// aborts the ongoing navigation. The fork's rule that back() while a link's
// guard waits leaves the link is in back_while_nested_guard_waits_test.dart.

final _guard = HeldGuard();

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [('Home', '/'), ('A', '/a')])
      NamedRouteDef(name: name, path: path, builder: (_, _) => NamedPage(name)),
    NamedRouteDef(
      name: 'Detail',
      path: '/detail',
      guards: [_guard],
      builder: (_, _) => const NamedPage('Detail'),
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
          builder: (_, _) => const NamedPage('One'),
        ),
        NamedRouteDef(
          name: 'Two',
          path: 'two',
          guards: [_guard],
          builder: (_, _) => const NamedPage('Two'),
        ),
      ],
    ),
  ],
);

// Steps back with [root] until its history can't, and returns the urls
// shown, the current one first.
Future<List<String>> _walkBack(WidgetTester tester, StackRouter root) async {
  final urls = [root.currentUrl];
  for (var i = 0; i < 8 && root.navigationHistory.canNavigateBack; i++) {
    root.back();
    await tester.pumpAndSettle();
    urls.add(root.currentUrl);
  }
  return urls;
}

void main() {
  setUp(() {
    _guard
      ..clear()
      ..holdCall();
  });

  // The page the app opens over Home, the link, the page on screen while
  // the guard decides, and its url.
  for (final (opened, link, shown, url) in [
    ('Tabs', '/tabs/two', 'One', '/tabs/one'),
    ('A', '/detail', 'A', '/a'),
  ]) {
    for (final saysYes in [true, false]) {
      testWidgets('back() while the guard of the link to $link decides leaves '
          'the link, and a ${saysYes ? 'yes' : 'no'} then changes nothing', (
        tester,
      ) async {
        final root = _router();
        await pumpRouterConfigApp(tester, root.config());
        unawaited(root.push(NamedRoute<Object?>(opened)));
        await tester.pumpAndSettle();
        unawaited(tester.binding.handlePushRoute(link));
        await tester.pumpAndSettle();

        root.back();
        await tester.pumpAndSettle();
        final afterBack = '${root.topRoute.name} ${root.currentUrl}';
        await (saysYes ? _guard.last.allow() : _guard.last.reject());
        await tester.pumpAndSettle();

        expect(
          (afterBack, '${root.topRoute.name} ${root.currentUrl}'),
          ('$shown $url', '$shown $url'),
        );
        expect(await _walkBack(tester, root), [url, '/']);
      });
    }
  }
}
