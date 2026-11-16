import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// pushAndPopUntil of a page that was not open, with pages named for its
// nested router whose guard then said no, was never taken back, even when
// its predicate removed nothing: Mail stayed on its inbox and the caller
// waited on a page it never asked for.
// Setup: First, and in some tests A and B over it, in the root router, in a
// shell's router and in a tab's router. Mail holds a nested router with
// Inbox as its first page and Message by id, whose guard the test answers.
// Steps: pushAndPopUntil of Mail with message 77, keeping First. Then the
// guard says no at once or later.
// Was: First and Mail on its inbox; the caller kept waiting.
// Should: when the call removed nothing, the stack and url are as before
// and the caller gets null, as for push. When it removed A and B, whose
// callers were answered as they left, Mail stays on its first page, as
// after replace, and its caller waits for its result. onFailure hears the
// no once either way.
// Native behavior this holds to: Flutter's Navigator.pushAndRemoveUntil
// removes the routes in the step that pushes, so a push that doesn't happen
// removes nothing; Android's conditional navigation pops back to the start
// destination when the check fails.
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
      for (final isAtOnce in [true, false]) {
        final from = isOverAB ? 'First, A, B' : 'First';
        testWidgets('${where.name}: pushAndPopUntil from $from, the guard '
            'says no ${isAtOnce ? 'at once' : 'later'}', (tester) async {
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
          // What a call that removes nothing leaves as it was.
          final before = isOverAB ? null : (_names(scope), router.currentUrl);
          _guard.mode = isAtOnce ? .answersNo : .holdsCall;
          var failures = 0;
          Object? got = #waiting;
          scope
              .pushAndPopUntil<Object?>(
                NamedRoute(
                  'Mail$s',
                  children: [
                    NamedRoute('Message$s', params: const {'id': '77'}),
                  ],
                ),
                predicate: (route) => route.settings.name == 'First$s',
                onFailure: (_) => failures++,
              )
              .then((result) => got = result)
              .ignore();
          await tester.pumpAndSettle();
          if (!isAtOnce) {
            await _guard.last.reject();
            await tester.pumpAndSettle();
          }

          expect(tester.takeException(), isNull);
          expect(_guard.askCount, 1);
          expect(failures, 1);
          if (before != null) {
            expect(_names(scope), before.$1);
            expect(router.currentUrl, before.$2);
            expect(got, isNull);
            return;
          }
          expect(_names(scope), ['First$s', 'Mail$s']);
          expect(find.text('Inbox$s'), findsOneWidget);
          expect(got, #waiting);
          await scope.maybePop();
          await tester.pumpAndSettle();
          expect(got, isNull, reason: 'the caller hears Mail close');
        });
      }
    }
  }
}
