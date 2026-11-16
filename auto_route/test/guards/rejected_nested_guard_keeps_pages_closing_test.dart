import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// A navigation that closes pages on its way into a page that was not open,
// whose nested router's guard then said no, left those pages closed. On
// Home with A over it, a link to message 13 of Mail brings Home below Mail,
// so it went back to Home, closing A, before Mail's guard was asked.
// Setup: Home at the root path, A pushed over it. Mail holds a nested router
// with Inbox as its first page and Message, whose guard the test answers.
// Steps: a platform link, or navigatePath with the pages below, goes to the
// message; navigate to Mail alone as a neighbor. Then the guard says no at
// once or later, with or without going back, or yes later.
// Was: Home and Mail on its inbox, or Home alone after a no that goes back.
// A was closed and its caller answered.
// Should: after a no, Home and A, at the url of A, with the caller of A
// still waiting, as the pages over an open page stay while its nested
// guards decide. After a yes, A closes as before, and Mail shows the
// message.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document and its url on screen; Android's conditional navigation pops
// back to the start destination when the check fails.
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
          path: 'message',
          guards: [_guard],
          builder: (_, _) => const Text('Message'),
        ),
      ],
    ),
  ],
);

List<String> _names(StackRouter router) => [
  for (final page in router.stack) page.routeData.name,
];

enum _Way { link, navigatePath, navigate }

enum _Answer { noAtOnce, noLater, noLaterGoingBack, yesLater }

void main() {
  for (final way in _Way.values) {
    for (final answer in _Answer.values) {
      // A no that goes back reverts a link the platform opened. After the
      // app's own call it steps back over A, as the history takes the entry
      // of the navigation still waiting for its guard as closed: not this
      // fix's to settle.
      if (way != .link && answer == .noLaterGoingBack) continue;
      testWidgets('${way.name} with Home below Mail, from Home and A, '
          '${answer.name}', (tester) async {
        _guard
          ..clear()
          ..mode = answer == .noAtOnce ? .answersNo : .holdsCall;
        final router = _router();
        await pumpRouterConfigApp(tester, router.config());
        Object? gotA = #waiting;
        router
            .push<Object?>(const NamedRoute('ARoute'))
            .then((result) => gotA = result)
            .ignore();
        await tester.pumpAndSettle();

        switch (way) {
          case .link:
            unawaited(tester.binding.handlePushRoute('/mail/message'));
          case .navigatePath:
            unawaited(
              router.navigatePath('/mail/message', includePrefixMatches: true),
            );
          // Names Mail alone: A stays under it, as before.
          case .navigate:
            unawaited(
              router.navigate(
                const NamedRoute(
                  'MailRoute',
                  children: [NamedRoute('MessageRoute')],
                ),
              ),
            );
        }
        await tester.pumpAndSettle();
        expect(_guard.askCount, 1);
        switch (answer) {
          case .noAtOnce:
            break;
          case .noLater:
            await _guard.last.reject();
          case .noLaterGoingBack:
            await _guard.last.reject(goBack: true);
          case .yesLater:
            await _guard.last.allow();
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        if (answer == .yesLater) {
          final isAKept = way == .navigate;
          expect(_names(router), [
            'HomeRoute',
            if (isAKept) 'ARoute',
            'MailRoute',
          ]);
          expect(find.text('Message'), findsOneWidget);
          expect(router.currentUrl, '/mail/message');
          expect(gotA, isAKept ? #waiting : isNull);
          return;
        }
        expect(_names(router), ['HomeRoute', 'ARoute']);
        expect(find.text('ARoute'), findsOneWidget);
        expect(router.currentUrl, '/a');
        expect(router.navigationHistory.length, 2);
        expect(gotA, #waiting);
      });
    }
  }
}
