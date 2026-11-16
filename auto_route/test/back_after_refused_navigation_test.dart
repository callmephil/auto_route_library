// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';
import 'utils/held_guard.dart';

// Off the web, back() walks the app's own history. After the app's own
// navigatePath into a page whose nested guard then said no, with a push made
// while the guard decided or with the guard's sign-in page backed out of,
// the refused navigation's entry stayed, so a later back() opened the page
// the guard had turned down. And when the guard said yes after a push made
// meanwhile, the page let in had its entry before that of the page under it,
// so back() skipped it. Found by the second review of the nested guards
// (found on the way, older than the batch).
//
// Native behavior this holds to: a Navigator's history is "populated" from
// its pages alone (Navigator.pages, packages/flutter/lib/src/widgets/
// navigator.dart 1610, Flutter 3.47.9), so a page a guard never let in has
// no place a pop can return to; and Navigator.pop takes the top-most route
// only (navigator.dart 5617 and 5652), so back() closes the pages in the
// order of the stack.
//
// Steps: on Home, or on Home, A, the app's navigatePath('/mail/77') or a
// platform link opens Mail with Inbox while Message's guard decides; the
// app pushes Settings, or the guard shows a sign-in page; then the guard
// answers, and back() walks to the first page.

final _guard = HeldGuard();

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('SettingsRoute', '/settings'),
      ('SignInRoute', '/sign-in'),
    ])
      NamedRouteDef(
        name: name,
        path: path,
        builder: (_, _) => Scaffold(body: Text(name)),
      ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'InboxRoute',
          path: '',
          builder: (_, _) => const Text('InboxRoute'),
        ),
        NamedRouteDef(
          name: 'MessageRoute',
          path: ':id',
          guards: [_guard],
          builder: (_, data) => Text('Message ${data.params.getString('id')}'),
        ),
      ],
    ),
  ],
);

// Opens Home and pushes [before] over it, then starts the way to /mail/77,
// whose guard holds its call.
Future<RootStackRouter> _open(
  WidgetTester tester, {
  required bool isLink,
  List<String> before = const [],
}) async {
  final router = _router();
  await pumpRouterConfigApp(tester, router.config());
  for (final page in before) {
    unawaited(router.push(NamedRoute(page)));
    await tester.pumpAndSettle();
  }
  if (isLink) {
    unawaited(tester.binding.handlePushRoute('/mail/77'));
  } else {
    unawaited(router.navigatePath('/mail/77', includePrefixMatches: true));
  }
  await tester.pumpAndSettle();
  return router;
}

// Steps back until the history can't, and returns the urls shown, the
// current one first.
Future<List<String>> _walkBack(
  WidgetTester tester,
  RootStackRouter router,
) async {
  final urls = [router.currentUrl];
  for (var i = 0; i < 8 && router.navigationHistory.canNavigateBack; i++) {
    router.back();
    await tester.pumpAndSettle();
    urls.add(router.currentUrl);
  }
  return urls;
}

void main() {
  setUp(() {
    _guard
      ..clear()
      ..holdCall();
  });

  for (final isLink in [false, true]) {
    final way = isLink ? 'A link' : "The app's navigatePath";
    group('$way to /mail/77 whose guard decides,', () {
      for (final before in [
        <String>[],
        const ['ARoute'],
      ]) {
        final from = before.isEmpty ? 'Home' : 'Home, A';
        testWidgets('from $from, Settings pushed meanwhile, then no: back() '
            'never opens Mail', (tester) async {
          final router = await _open(tester, isLink: isLink, before: before);
          unawaited(router.push(const NamedRoute('SettingsRoute')));
          await tester.pumpAndSettle();
          await _guard.last.reject();
          await tester.pumpAndSettle();
          expect(await _walkBack(tester, router), [
            '/settings',
            if (before.isNotEmpty) '/a',
            '/',
          ]);
        });

        testWidgets('from $from, the guard shows a sign-in page the user '
            'backs out of: back() never opens Mail', (tester) async {
          final router = await _open(tester, isLink: isLink, before: before);
          unawaited(_guard.last.redirectUntil(const NamedRoute('SignInRoute')));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(await _walkBack(tester, router), [
            if (before.isNotEmpty) '/a',
            '/',
          ]);
        });

        testWidgets('from $from, then reject(goBack: true): back to the page '
            'before', (tester) async {
          final router = await _open(tester, isLink: isLink, before: before);
          await _guard.last.reject(goBack: true);
          await tester.pumpAndSettle();
          expect(await _walkBack(tester, router), [
            if (before.isNotEmpty) '/a',
            '/',
          ]);
        });
      }

      testWidgets('from Home, Settings pushed meanwhile, then yes: back() '
          'shows Message, then the page under it', (tester) async {
        final router = await _open(tester, isLink: isLink);
        unawaited(router.push(const NamedRoute('SettingsRoute')));
        await tester.pumpAndSettle();
        await _guard.last.allow();
        await tester.pumpAndSettle();
        // back() to Message, which is open, navigates to it, and its guard
        // is asked again; it lets it through.
        _guard.answerYes();
        // Inbox went in under Settings, so it has an entry of its own, also
        // after a link, as the web's entry list gives it one there.
        expect(await _walkBack(tester, router), [
          '/settings',
          '/mail/77',
          '/mail',
          '/',
        ]);
      });
    });
  }
}
