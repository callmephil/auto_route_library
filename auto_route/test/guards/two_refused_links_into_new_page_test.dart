import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// callmephil/auto_route_library#11: two links that bring only their own
// page, into a page whose nested guard is slow and rejects both, left the
// page open on its first nested page.
// Setup: Home at '/', A at '/a', and Mail at '/mail' with a stack router:
// Inbox as its first page, and Message by id, whose guard the test answers.
// The router config has includePrefixMatches: false, as the web's default.
// Steps: push A over Home and keep its future. Open the link '/mail/77'.
// While the guard waits, open it again. The guard answers each ask, in
// either order.
// Was: after two noes, Home, A and Mail on its inbox, at '/mail'. The second
// link reached Mail again, so the first no kept the page as reached, though
// the second link was refused too; and that link had put Mail on again as a
// new page, which the take-back did not find.
// Should: after two noes, Home and A at '/a', and the push of A still
// waits. A yes to either ask shows one Mail page with message 77, at
// '/mail/77'.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document and its url on screen (HTML standard). Flutter's Navigator
// shows only the pages of its pages list.
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

// The answers, first to the first ask, then to the second, or the other
// way round.
enum _Answers {
  secondNoThenFirstNo,
  firstNoThenSecondNo,
  firstNoThenSecondYes,
  secondNoThenFirstYes,
  firstYesThenSecondNo,
}

void main() {
  for (final answers in _Answers.values) {
    testWidgets('Two links to message 77, ${answers.name}', (tester) async {
      _guard
        ..clear()
        ..holdCall();
      final router = _router();
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: false),
      );
      Object? gotA = #waiting;
      router
          .push<Object?>(const NamedRoute('ARoute'))
          .then((result) => gotA = result)
          .ignore();
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        unawaited(tester.binding.handlePushRoute('/mail/77'));
        await tester.pumpAndSettle();
      }
      expect(_guard.askCount, 2);
      final (first, second) = (_guard.first, _guard.last);
      Future<void> answer(HeldAsk ask, {required bool isYes}) async {
        await (isYes ? ask.allow() : ask.reject());
        await tester.pumpAndSettle();
      }

      switch (answers) {
        case .secondNoThenFirstNo:
          await answer(second, isYes: false);
          await answer(first, isYes: false);
        case .firstNoThenSecondNo:
          await answer(first, isYes: false);
          await answer(second, isYes: false);
        case .firstNoThenSecondYes:
          await answer(first, isYes: false);
          await answer(second, isYes: true);
        case .secondNoThenFirstYes:
          await answer(second, isYes: false);
          await answer(first, isYes: true);
        case .firstYesThenSecondNo:
          await answer(first, isYes: true);
          await answer(second, isYes: false);
      }

      expect(tester.takeException(), isNull);
      final names = [for (final page in router.stack) page.routeData.name];
      final isBothNo =
          answers == .secondNoThenFirstNo || answers == .firstNoThenSecondNo;
      if (isBothNo) {
        expect(names, ['HomeRoute', 'ARoute']);
        expect(router.currentUrl, '/a');
      } else {
        expect(names, ['HomeRoute', 'ARoute', 'MailRoute']);
        expect(find.text('Message 77'), findsOneWidget);
        expect(router.currentUrl, '/mail/77');
        expect(
          router
              .innerRouterOf<StackRouter>('MailRoute')
              ?.stack
              .lastOrNull
              ?.name,
          'MessageRoute',
        );
      }
      expect(gotA, #waiting, reason: 'A stays open');
    });
  }
}
