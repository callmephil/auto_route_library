import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// pushAll with a page that was not open, holding pages named for its nested
// router, before the batch's last page: that router's guard said no while
// the page sat under the last one, and the page stayed on its first page,
// under the last page; onFailure never heard of it.
// Setup: First, and in some tests A and B over it, in the root router, in a
// shell's router and in a tab's router. Mail holds a nested router with
// Inbox as its first page and Message by id, whose guard the test answers.
// Steps: pushAll of Mail with message 77, then Settings. Then the guard says
// no at once or later, or yes.
// Was: Mail on its inbox under Settings, and no failure heard.
// Should: a guard that rejects one of the routes rejects them all, as
// pushAll's doc says: after a no the stack and url are as before, and
// onFailure hears it once. After a yes, Mail shows the message under
// Settings.
// Native behavior this holds to: Flutter's Navigator takes a new list of
// pages as one update, and Android applies a fragment transaction as one
// atomic set of operations; on the web a canceled navigation leaves the
// document and its url on screen.
late HeldGuard _guard;

NamedRouteDef _page(String name, String path) => .new(
  name: name,
  path: path,
  builder: (_, _) => Scaffold(body: Text(name)),
);

NamedRouteDef _mail(String suffix, String path) => .new(
  name: 'Mail$suffix',
  path: path,
  builder: (_, _) => const Scaffold(body: AutoRouter()),
  children: [
    NamedRouteDef(
      name: 'Inbox$suffix',
      path: '',
      builder: (_, _) => Text('Inbox$suffix'),
    ),
    NamedRouteDef(
      name: 'Message$suffix',
      path: ':id',
      guards: [_guard],
      builder: (_, _) => Text('Message$suffix'),
    ),
  ],
);

List<NamedRouteDef> _pages(String suffix, {required bool isNested}) => [
  _page('First$suffix', isNested ? '' : '/'),
  _page('Settings$suffix', isNested ? 'settings' : '/settings'),
  _page('A$suffix', isNested ? 'a' : '/a'),
  _page('B$suffix', isNested ? 'b' : '/b'),
  _mail(suffix, isNested ? 'mail' : '/mail'),
];

RootStackRouter _router() => .build(
  routes: [
    ..._pages('', isNested: false),
    NamedRouteDef(
      name: 'Shell',
      path: '/shell',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: _pages('S', isNested: true),
    ),
    NamedRouteDef(
      name: 'Tabs',
      path: '/tabs',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(routes: [NamedRoute('Tab1'), NamedRoute('Tab2')]),
      ),
      children: [
        NamedRouteDef(
          name: 'Tab1',
          path: 'one',
          builder: (_, _) => const AutoRouter(),
          children: _pages('T', isNested: true),
        ),
        _page('Tab2', 'two'),
      ],
    ),
  ],
);

List<String> _names(StackRouter router) => [
  for (final page in router.stack) page.routeData.name,
];

enum _Where { root, shell, tab }

String _suffix(_Where where) => switch (where) {
  .root => '',
  .shell => 'S',
  .tab => 'T',
};

void main() {
  setUp(() => _guard = HeldGuard());

  for (final where in _Where.values) {
    for (final isOverAB in [false, true]) {
      for (final answer in ['no at once', 'no later', 'yes later']) {
        final from = isOverAB ? 'First, A, B' : 'First';
        testWidgets('${where.name}: pushAll of Mail then Settings from $from, '
            'the guard says $answer', (tester) async {
          final s = _suffix(where);
          final router = _router();
          await pumpRouterConfigApp(tester, router.config());
          StackRouter scope = router;
          if (where == .shell) {
            unawaited(router.navigatePath('/shell'));
            await tester.pumpAndSettle();
            scope = router.innerRouterOf<StackRouter>('Shell')!;
          } else if (where == .tab) {
            unawaited(router.navigatePath('/tabs/one'));
            await tester.pumpAndSettle();
            scope = router
                .innerRouterOf<TabsRouter>('Tabs')!
                .innerRouterOf<StackRouter>('Tab1')!;
          }
          if (isOverAB) {
            for (final name in ['A$s', 'B$s']) {
              unawaited(scope.push(NamedRoute(name)));
              await tester.pumpAndSettle();
            }
          }
          final before = _names(scope);
          final urlBefore = router.currentUrl;
          _guard.mode = answer == 'no at once' ? .answersNo : .holdsCall;
          var failures = 0;
          var isDone = false;
          scope
              .pushAll([
                NamedRoute(
                  'Mail$s',
                  children: [
                    NamedRoute('Message$s', params: const {'id': '77'}),
                  ],
                ),
                NamedRoute('Settings$s'),
              ], onFailure: (_) => failures++)
              .then((_) => isDone = true)
              .ignore();
          await tester.pumpAndSettle();
          if (answer != 'no at once') {
            await (answer == 'yes later'
                ? _guard.last.allow()
                : _guard.last.reject());
            await tester.pumpAndSettle();
          }

          expect(tester.takeException(), isNull);
          expect(_guard.askCount, 1);
          expect(isDone, isTrue, reason: "pushAll's caller is answered");
          if (answer == 'yes later') {
            expect(_names(scope), [...before, 'Mail$s', 'Settings$s']);
            expect(find.text('Message$s', skipOffstage: false), findsOneWidget);
            expect(failures, 0);
            return;
          }
          expect(_names(scope), before);
          expect(router.currentUrl, urlBefore);
          expect(find.text('Inbox$s', skipOffstage: false), findsNothing);
          expect(failures, 1);
        });
      }
    }
  }
}
