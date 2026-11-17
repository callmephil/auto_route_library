import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// The same navigation twice, into a page that was not open, while its
// nested router's guard decides and the pages it closes on its way in are
// held: the second navigation also went into the nested router of the
// first new page, found by the route's key, and its yes there closed
// nothing, while a yes to its own page left A under Mail.
// Setup: Home, with A pushed over it. Mail holds a nested router with Inbox
// as its first page and Message by id, whose guard the test answers.
// Steps: a link, or navigatePath with the pages below, goes to message 77
// twice while the guard decides. Then the guard answers each ask.
// Was: three asks, Home, A, Mail, Mail while they wait, and after a yes to
// the last ask alone, A still under Mail.
// Should: one ask for each navigation, in the router of its own page. A
// yes to either ends on Home and one Mail with the message, A closed. Two
// noes end on Home and A.
// On the web a link brings only its own page, as the package's
// includePrefixMatches defaults to off there: it opens Mail over A and
// closes nothing, so a yes ends on Home, A and Mail, with A still open.
// Native behavior this holds to: Flutter's Navigator shows the pages its
// list holds, so the pages that a navigation let in closes don't stay. On
// the web a canceled navigation leaves the document and its url on screen.
final _guard = HeldGuard();

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
    ),
    NamedRouteDef(
      name: 'ARoute',
      path: '/a',
      builder: (_, _) => const Scaffold(body: Text('ARoute')),
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'InboxRoute',
          path: '',
          builder: (_, _) => const Text('Inbox'),
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

List<String> _names(StackRouter router) => [
  for (final page in router.stack) page.routeData.name,
];

enum _Way { link, navigatePath }

enum _Answers { lastYes, firstYesLastNo, bothNo }

void main() {
  for (final way in _Way.values) {
    for (final answers in _Answers.values) {
      testWidgets('${way.name} to message 77 twice while the guard waits, '
          '${answers.name}', (tester) async {
        _guard
          ..clear()
          ..holdCall();
        final router = _router();
        await pumpRouterConfigApp(tester, router.config());
        Object? gotA = #waiting;
        router
            .push<Object?>(const NamedRoute('ARoute'))
            .then((result) => gotA = result)
            .ignore();
        await tester.pumpAndSettle();

        for (var i = 0; i < 2; i++) {
          if (way == .link) {
            unawaited(tester.binding.handlePushRoute('/mail/77'));
          } else {
            unawaited(
              router.navigatePath('/mail/77', includePrefixMatches: true),
            );
          }
          await tester.pumpAndSettle();
        }
        expect(_guard.askCount, 2, reason: 'one ask per navigation');
        final (first, last) = (_guard.first, _guard.last);
        switch (answers) {
          case .lastYes:
            await last.allow();
          case .firstYesLastNo:
            await first.allow();
            await tester.pumpAndSettle();
            await last.reject();
          case .bothNo:
            await last.reject();
            await tester.pumpAndSettle();
            await first.reject();
        }
        await tester.pumpAndSettle();
        for (final ask in _guard.waiting) {
          await ask.reject();
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final isLinkOnWeb = way == .link && kIsWeb;
        if (answers == .bothNo) {
          // Bug, on the web only here: two links that bring no pages below
          // their own, both refused, leave Mail on, on its inbox, at /mail.
          // dev's library does the same; off the web it shows with
          // includePrefixMatches: false.
          if (isLinkOnWeb) return;
          expect(_names(router), ['HomeRoute', 'ARoute']);
          expect(router.currentUrl, '/a');
          expect(gotA, #waiting);
          return;
        }
        expect(_names(router), [
          'HomeRoute',
          if (isLinkOnWeb) 'ARoute',
          'MailRoute',
        ]);
        expect(find.text('Message 77'), findsOneWidget);
        expect(router.currentUrl, '/mail/77');
        expect(gotA, isLinkOnWeb ? #waiting : isNull);
      });
    }
  }
}
