import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard's "no" inside a nested router that was not built yet never
// reached the onFailure of the call that navigated there, though
// navigatePath's doc promises a RejectedByGuardFailure.
// Setup: Mail is a shell that is not open. MailTab is a tab never opened.
// Each holds Inbox as its first page and Message by id. The guard of
// Message rejects message 13 at once, and decides about message 77 only
// when the test answers.
// Steps: the app goes to a message with onFailure, by each of the calls
// navigatePath, navigate and pushPath.
// Was: onFailure heard nothing.
// Should: onFailure hears one RejectedByGuardFailure for the message, once
// the guard has said no.
// Native behavior this holds to: Android's handleDeepLink and the iOS app
// delegate's method that opens a url both answer whether the app handled
// the link, so a navigation turned down is reported to who asked for it.
Completer<bool>? _slow;

final _guard = AutoRouteGuard.simple((resolver, _) async {
  if (resolver.route.params.getString('id') == '13') return resolver.reject();
  final answer = _slow = Completer<bool>();
  await answer.future ? resolver.next() : resolver.reject();
});

List<NamedRouteDef> _mailChildren() => [
  NamedRouteDef(
    name: 'InboxRoute',
    path: '',
    builder: (_, _) => const Text('Inbox'),
  ),
  NamedRouteDef(
    name: 'MessageRoute',
    path: ':id',
    guards: [_guard],
    builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
  ),
];

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: _mailChildren(),
    ),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute('FirstTab'), NamedRoute('MailTab')],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'FirstTab',
          path: 'first',
          builder: (_, _) => const Text('FirstTab'),
        ),
        NamedRouteDef(
          name: 'MailTab',
          path: 'mail',
          builder: (_, _) => const AutoRouter(),
          children: _mailChildren(),
        ),
      ],
    ),
  ],
);

enum _Way { navigatePath, navigate, pushPath }

void main() {
  setUp(() => _slow = null);

  for (final isTab in [false, true]) {
    final where = isTab ? 'a tab never opened' : 'a shell not open';
    for (final way in _Way.values) {
      // pushPath pushes the tabs page anew rather than reaching its tab.
      if (isTab && way == .pushPath) continue;
      for (final id in ['13', '77']) {
        testWidgets('${way.name} to message $id in $where: onFailure hears '
            'the rejection', (tester) async {
          final router = _router();
          await pumpRouterConfigApp(tester, router.config());
          if (isTab) {
            unawaited(router.navigatePath('/tabs/first'));
            await tester.pumpAndSettle();
          }
          final failures = <NavigationFailure>[];
          final path = isTab ? '/tabs/mail/$id' : '/mail/$id';
          switch (way) {
            case .navigatePath:
              unawaited(router.navigatePath(path, onFailure: failures.add));
            case .navigate:
              final message = NamedRoute('MessageRoute', params: {'id': id});
              unawaited(
                router.navigate(
                  isTab
                      ? NamedRoute(
                          'TabsRoute',
                          children: [
                            NamedRoute('MailTab', children: [message]),
                          ],
                        )
                      : NamedRoute('MailRoute', children: [message]),
                  onFailure: failures.add,
                ),
              );
            case .pushPath:
              router.pushPath<void>(path, onFailure: failures.add).ignore();
          }
          await tester.pumpAndSettle();
          if (id == '77') {
            expect(failures, isEmpty, reason: 'the guard has not answered');
            _slow!.complete(false);
            await tester.pumpAndSettle();
          }

          expect(tester.takeException(), isNull);
          expect(failures, hasLength(1));
          expect(
            failures.singleOrNull,
            isA<RejectedByGuardFailure>().having(
              (failure) => failure.route.name,
              'route',
              'MessageRoute',
            ),
          );
        });
      }
    }
  }
}
