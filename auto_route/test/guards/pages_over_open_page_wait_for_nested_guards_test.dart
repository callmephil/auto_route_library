import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A navigation into the nested router of an open page, with pages pushed
// over that page, closed those pages as soon as the router above let the
// page through, before the guards of its nested router answered; a no left
// them closed, with the dialog over them.
// Setup: Home, at the root path, holds a nested router with Feed as its
// first page and Message by id. The guard of Message rejects message 13 at
// once, and decides about message 77 only when the test answers. Settings
// and Details are pushed over Home, and a dialog named Draft over Details.
// Steps: a link, navigatePath or navigate goes to a message in Home's
// router. Then the guard of 77 says no or yes.
// Was: Settings, Details and the dialog closed at once and stayed closed.
// Should: they stay while the guard decides, and after a no, with the url
// unchanged. A yes closes them and shows the message.
// Native behavior this holds to: the dialogs over that page already wait
// for those guards; on the web a canceled navigation leaves the document
// on screen, and on iOS a segue whose shouldPerformSegue answers false
// leaves the view controllers as they are.
Completer<bool>? _slow;

final _guard = AutoRouteGuard.simple((resolver, _) async {
  if (resolver.route.params.getString('id') == '13') return resolver.reject();
  final answer = _slow = Completer<bool>();
  await answer.future ? resolver.next() : resolver.reject();
});

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'FeedRoute',
          path: '',
          builder: (_, _) => const Text('Feed'),
        ),
        NamedRouteDef(
          name: 'MessageRoute',
          path: 'message/:id',
          guards: [_guard],
          builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
        ),
      ],
    ),
    for (final (name, path) in [
      ('SettingsRoute', '/settings'),
      ('DetailsRoute', '/details'),
    ])
      NamedRouteDef(
        name: name,
        path: path,
        builder: (_, _) => Scaffold(body: Text(name)),
      ),
  ],
);

List<String> _names(StackRouter? router) => [
  ...?router?.stack.map((page) => page.routeData.name),
];

enum _Way { link, navigatePath, navigate }

enum _Answer { rejectsAtOnce, waitsThenNo, waitsThenYes }

void main() {
  setUp(() => _slow = null);

  for (final way in _Way.values) {
    for (final answer in _Answer.values) {
      final id = answer == .rejectsAtOnce ? '13' : '77';
      testWidgets('${way.name} to message $id under Settings and Details, '
          '${answer.name}', (tester) async {
        final router = _router();
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('SettingsRoute')));
        await tester.pumpAndSettle();
        unawaited(router.push(const NamedRoute('DetailsRoute')));
        await tester.pumpAndSettle();
        showDialog<void>(
          context: router.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Draft')),
        );
        await tester.pumpAndSettle();
        const before = ['HomeRoute', 'SettingsRoute', 'DetailsRoute'];
        expect([..._names(router), router.currentUrl], [...before, '/details']);

        switch (way) {
          case .link:
            await tester.binding.handlePushRoute('/message/$id');
          case .navigatePath:
            unawaited(router.navigatePath('/message/$id'));
          case .navigate:
            unawaited(
              router.navigate(
                NamedRoute(
                  'HomeRoute',
                  children: [
                    NamedRoute('MessageRoute', params: {'id': id}),
                  ],
                ),
              ),
            );
        }
        await tester.pumpAndSettle();
        if (answer != .rejectsAtOnce) {
          expect(_slow?.isCompleted, isFalse, reason: 'the guard waits');
          expect(_names(router), before, reason: 'while it decides');
          expect(find.text('Draft'), findsOneWidget, reason: 'meanwhile');
          // On the web a link's url shows at once and stays while it waits.
          expect(
            router.currentUrl,
            kIsWeb && way == .link ? '/message/77' : '/details',
            reason: 'meanwhile',
          );
          _slow!.complete(answer == .waitsThenYes);
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        final home = router.innerRouterOf<StackRouter>('HomeRoute');
        if (answer == .waitsThenYes) {
          expect(_names(router), ['HomeRoute']);
          expect(_names(home), ['FeedRoute', 'MessageRoute']);
          expect(find.text('Mail 77'), findsOneWidget);
          expect(find.text('Draft'), findsNothing);
          expect(router.currentUrl, '/message/77');
          return;
        }
        expect(_names(router), before);
        expect(_names(home), ['FeedRoute']);
        expect(find.text('Draft'), findsOneWidget);
        expect(find.text('DetailsRoute', skipOffstage: false), findsOneWidget);
        expect(router.currentUrl, '/details');
      });
    }
  }

  // A guard that shows a sign-in page in Home's router while it decides:
  // the pages over Home leave first, so the user sees it.
  testWidgets('A guard that shows a sign-in page in Home takes the pages '
      'over Home off first', (tester) async {
    Completer<bool>? signIn;
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(body: AutoRouter()),
          children: [
            NamedRouteDef(
              name: 'FeedRoute',
              path: '',
              builder: (_, _) => const Text('Feed'),
            ),
            NamedRouteDef(
              name: 'SignInRoute',
              path: 'sign-in',
              builder: (_, _) => const Text('SignIn'),
            ),
            NamedRouteDef(
              name: 'MessageRoute',
              path: 'message/:id',
              guards: [
                AutoRouteGuard.simple((resolver, _) async {
                  final done = signIn = Completer<bool>();
                  unawaited(
                    resolver.redirectUntil(const NamedRoute('SignInRoute')),
                  );
                  await done.future ? resolver.next() : resolver.reject();
                }),
              ],
              builder: (_, _) => const Text('Message'),
            ),
          ],
        ),
        NamedRouteDef(
          name: 'SettingsRoute',
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('SettingsRoute')),
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('SettingsRoute')));
    await tester.pumpAndSettle();

    unawaited(router.navigatePath('/message/5'));
    await tester.pumpAndSettle();

    expect(find.text('SignIn'), findsOneWidget);
    expect(_names(router), ['HomeRoute']);

    signIn!.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Message'), findsOneWidget);
    expect(router.currentUrl, '/message/5');
  });
}
