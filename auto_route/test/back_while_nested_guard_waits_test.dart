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

// Off the web, back() walks the app's own history. A link into a nested
// router whose guard was still deciding lost its entry once the root router
// notified or back() ran meanwhile: back() and reject(goBack: true) then did
// nothing, and after a yes the page on screen had no entry, so back()
// couldn't leave it. The same with the app's own push of a page with its
// nested pages: back() while the guard there decided closed the page under
// it too. The history took the entry's page for open, and then for once
// open, while the way to it crossed a nested router not built yet; once that
// router was built without the page the guard held out, the entry looked
// like that of a page that had closed. Found by the second review of the
// batch's history commits (N1, and O1, older).
//
// Native behavior this holds to: Navigator.pop "Pop[s] the top-most route
// off the navigator" (packages/flutter/lib/src/widgets/navigator.dart 5617,
// Flutter 3.47.9), taking only the last present route (5652): back() closes
// the page on top and nothing under it, and every page it must reach needs
// an entry. NavigationResolver.reject(goBack: true) "also goes back"
// (auto_route_guard.dart).
//
// Steps: on H, A, the platform hands the app a link into the shell or a
// tab's router whose page's guard waits; meanwhile the root may notify, or
// back() runs; then the guard answers. Or the app pushes the shell with its
// pages, and back() runs while the guard waits.

final _guard = HeldGuard();

RootStackRouter _router() => .build(
  routes: [
    for (final page in ['H', 'A'])
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
            path: page == 'X' ? '' : 'y',
            builder: (_, _) => NamedPage(page),
          ),
        NamedRouteDef(
          name: 'GX',
          path: 'gx',
          guards: [_guard],
          builder: (_, _) => const NamedPage('GX'),
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
            NamedRouteDef(
              name: 'OX',
              path: '',
              builder: (_, _) => const NamedPage('OX'),
            ),
            NamedRouteDef(
              name: 'OGX',
              path: 'gx',
              guards: [_guard],
              builder: (_, _) => const NamedPage('OGX'),
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

// Opens H, A, then hands the app [link], whose guard holds its call.
Future<RootStackRouter> _openAtLink(WidgetTester tester, String link) async {
  final root = _router();
  await pumpRouterConfigApp(tester, root.config());
  unawaited(root.push(const NamedRoute('A')));
  await tester.pumpAndSettle();
  unawaited(tester.binding.handlePushRoute(link));
  await tester.pumpAndSettle();
  return root;
}

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

typedef _Wait = void Function(RootStackRouter root);

void main() {
  setUp(() {
    _guard
      ..clear()
      ..holdCall();
  });

  // What happens while the guard waits.
  final waits = <String, _Wait?>{
    'nothing else': null,
    // Stands for any notification of the root meanwhile, such as a change
    // in another nested router.
    'a root notification': (root) => root.notifyListeners(),
  };

  for (final (host, link, opened) in [
    ('shell', '/shell/gx', '/shell'),
    ("tab's router", '/tabs/one/gx', '/tabs/one'),
  ]) {
    group('A link to $link on H, A whose guard waits in the $host,', () {
      for (final MapEntry(key: meanwhile, value: wait) in waits.entries) {
        testWidgets('$meanwhile, then yes: back() walks to H', (tester) async {
          final root = await _openAtLink(tester, link);
          wait?.call(root);
          await _guard.last.allow();
          await tester.pumpAndSettle();
          expect(await _walkBack(tester, root), [link, '/']);
        });

        testWidgets('$meanwhile, then reject(goBack: true): back to H', (
          tester,
        ) async {
          final root = await _openAtLink(tester, link);
          wait?.call(root);
          await _guard.last.reject(goBack: true);
          await tester.pumpAndSettle();
          expect(root.stack.map((page) => page.name), ['H']);
          expect(root.navigationHistory.length, 1);
        });

        testWidgets('$meanwhile, then back() while it waits goes to H, and '
            'a no then changes nothing', (tester) async {
          final root = await _openAtLink(tester, link);
          wait?.call(root);
          root.back();
          await tester.pumpAndSettle();
          final whileWaiting = root.stack.map((page) => page.name).join(' ');
          await _guard.last.reject();
          await tester.pumpAndSettle();
          expect(whileWaiting, 'H');
          expect(root.stack.map((page) => page.name), ['H']);
          expect(root.navigationHistory.length, 1);
        });
      }

      testWidgets('then no: back() walks from the page shown to H', (
        tester,
      ) async {
        final root = await _openAtLink(tester, link);
        await _guard.last.reject();
        await tester.pumpAndSettle();
        expect(await _walkBack(tester, root), [opened, '/']);
      });
    });
  }

  // Neighbor: an entry counts as once open only while a stack holds its
  // page; the entry of a shell whose own router was emptied still leaves
  // with the shell.
  testWidgets('removeUntil A, not scoped, from the shell on X, Y over H, A '
      'leaves H, A and their entries', (tester) async {
    final root = _router();
    await pumpRouterConfigApp(tester, root.config());
    for (final page in ['A', 'Shell']) {
      unawaited(root.push(NamedRoute(page)));
      await tester.pumpAndSettle();
    }
    final shell = root.innerRouterOf<StackRouter>('Shell')!;
    unawaited(shell.push(const NamedRoute('Y')));
    await tester.pumpAndSettle();
    shell.removeUntil((data) => data.name == 'A', scoped: false);
    await tester.pumpAndSettle();
    expect(root.stack.map((page) => page.name), ['H', 'A']);
    expect(await _walkBack(tester, root), ['/a', '/']);
  });

  testWidgets('The app pushes Shell with X, GX on H, A; back() while the '
      'guard waits closes the shell only', (tester) async {
    final root = _router();
    await pumpRouterConfigApp(tester, root.config());
    unawaited(root.push(const NamedRoute('A')));
    await tester.pumpAndSettle();
    unawaited(
      root.push(
        const NamedRoute(
          'Shell',
          children: [NamedRoute('X'), NamedRoute('GX')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    root.back();
    await tester.pumpAndSettle();
    await _guard.last.reject();
    await tester.pumpAndSettle();
    expect(root.stack.map((page) => page.name), ['H', 'A']);
    expect(await _walkBack(tester, root), ['/a', '/']);
  });
}
