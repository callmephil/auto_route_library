// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';
import 'utils/held_guard.dart';

// Off the web, back() walks the app's own history. After a link or the
// app's own navigatePath into Mail's message 77, whose guard in Mail's
// nested router let it in after the app had pushed Settings meanwhile, the
// first back() never left Settings: it navigated into Mail again, the router
// asked the message's guard again, and since 11219ce0 the pages over an
// open page stay until a guard in that page's router answers. A guard that
// takes its time held Settings on screen. Found by the batch's final check
// (worse than dev 921fce58).
//
// Native behavior this holds to: one back closes the page on top and shows
// the one under it, which is already open: Navigator.pop "Pop[s] the
// top-most route off the navigator" (packages/flutter/lib/src/widgets/
// navigator.dart 5617, Flutter 3.47.9); Android's back "returns the user to
// the previous destination" on the back stack (developer.android.com,
// guide/navigation/backstack); UINavigationController.popViewController
// "pops the top view controller" (developer.apple.com). None of them asks
// anything before the page under it shows again.
//
// Steps: on Home, or on Home, A, a link or the app's navigatePath opens Mail
// on message 77 while its guard decides; meanwhile the app pushes Settings
// (or Settings and Profile, or pushes Settings and pops it); the guard says
// yes or no; then back() is called until it stops. The guard is asked again
// when back() returns to the open message, and answers then or never.

final _guard = HeldGuard();

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('SettingsRoute', '/settings'),
      ('ProfileRoute', '/profile'),
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

typedef _Meanwhile = Future<void> Function(
  WidgetTester tester,
  RootStackRouter router,
);

Future<void> _push(
  WidgetTester tester,
  RootStackRouter router,
  List<String> pages,
) async {
  for (final page in pages) {
    unawaited(router.push(NamedRoute(page)));
    await tester.pumpAndSettle();
  }
}

// What the app does while the guard decides, the pages it leaves over
// Mail, the one on top first, and whether it leaves Inbox shown on its own
// at /mail meanwhile.
final Map<String, (_Meanwhile, List<String>, bool)> _meanwhiles = {
  'pushes Settings': (
    (tester, router) => _push(tester, router, ['SettingsRoute']),
    ['/settings'],
    false,
  ),
  'pushes Settings and Profile': (
    (tester, router) =>
        _push(tester, router, ['SettingsRoute', 'ProfileRoute']),
    ['/profile', '/settings'],
    false,
  ),
  'pushes Settings and pops it': (
    (tester, router) async {
      await _push(tester, router, ['SettingsRoute']);
      router.pop();
    },
    [],
    true,
  ),
};

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
        for (final MapEntry(key: meanwhile, value: (act, over, isInboxShown))
            in _meanwhiles.entries) {
          for (final isAskAnswered in [false, true]) {
            final asked = isAskAnswered
                ? 'answers at once when back() asks again'
                : 'never answers when back() asks again';
            testWidgets('from $from, the app $meanwhile, then yes, and the '
                'guard $asked: back() closes one page per call', (
              tester,
            ) async {
              final router = await _open(
                tester,
                isLink: isLink,
                before: before,
              );
              await act(tester, router);
              await tester.pumpAndSettle();
              await _guard.last.allow();
              await tester.pumpAndSettle();
              if (isAskAnswered) _guard.answerYes();
              // A link's pages share its entry, unless Inbox was shown on its
              // own meanwhile; the app's navigatePath gives Inbox, the page
              // under the message, an entry of its own. A, which the
              // navigation took off, has none.
              expect(await _walkBack(tester, router), [
                ...over,
                '/mail/77',
                if (!isLink || isInboxShown) '/mail',
                '/',
              ]);
            });
          }

          testWidgets('from $from, the app $meanwhile, then no: back() never '
              'opens Mail', (tester) async {
            final router = await _open(tester, isLink: isLink, before: before);
            await act(tester, router);
            await tester.pumpAndSettle();
            await _guard.last.reject();
            await tester.pumpAndSettle();
            // A refused navigation changes nothing: A, held open while the
            // guard decided, stays.
            expect(await _walkBack(tester, router), [
              ...over,
              if (before.isNotEmpty) '/a',
              '/',
            ]);
          });
        }
      }
    });
  }
}
