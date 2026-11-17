import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// push of a page that was not open, with the pages of its nested router,
// whose guard there then said no, left the page on, on its first page. A
// link, navigatePath, navigate and pushPath took it back already.
// Setup: Home at the root path, and A pushed over it in some tests. Mail
// holds a nested router with Inbox as its first page and Message, whose
// guard the test answers.
// Steps: push of Mail with Message as its child. Then the guard says no
// at once or later, or yes later.
// Was: Home and Mail on its inbox, at the url of Mail.
// Should: a no leaves the stack and the url as before the call, and the
// caller of push gets null. A yes shows the message.
// Native behavior this holds to: Android's conditional navigation pops
// back from a destination whose check fails; on the web a canceled
// navigation leaves the document and its url on screen.
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

enum _Answer { noAtOnce, noLater, yesLater }

void main() {
  for (final isOverA in [false, true]) {
    for (final answer in _Answer.values) {
      testWidgets('push of Mail with Message on '
          '${isOverA ? 'Home, A' : 'Home'}, ${answer.name}', (tester) async {
        _guard
          ..clear()
          ..mode = answer == .noAtOnce ? .answersNo : .holdsCall;
        final router = _router();
        await pumpRouterConfigApp(tester, router.config());
        if (isOverA) {
          unawaited(router.push(const NamedRoute('ARoute')));
          await tester.pumpAndSettle();
        }
        final before = _names(router);
        final urlBefore = router.currentUrl;

        Object? got = #waiting;
        router
            .push<Object?>(
              const NamedRoute(
                'MailRoute',
                children: [NamedRoute('MessageRoute')],
              ),
            )
            .then((result) => got = result)
            .ignore();
        await tester.pumpAndSettle();
        expect(_guard.askCount, 1);
        if (answer != .noAtOnce) {
          await (answer == .yesLater
              ? _guard.last.allow()
              : _guard.last.reject());
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        if (answer == .yesLater) {
          expect(_names(router), [...before, 'MailRoute']);
          expect(find.text('Message'), findsOneWidget);
          expect(got, #waiting);
          return;
        }
        expect(_names(router), before);
        expect(router.currentUrl, urlBefore);
        // The headless runner in Chrome writes no browser entries to count.
        if (!kIsWeb) {
          expect(router.navigationHistory.length, before.length);
        }
        expect(find.text('Inbox', skipOffstage: false), findsNothing);
        expect(got, isNull);
      });
    }
  }
}
