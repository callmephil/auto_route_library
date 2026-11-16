import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// A navigate with a result type to a page already open that holds a stack
// of pages, a shell, waited until the shell closed and then gave its own
// caller null, where push of the shell gets the result it is popped with.
// The same with other params or the same, with a child named, under another
// page, and behind a guard of the shell's router that waits and lets it in.
// A navigate to a plain page that is open gets its result, since e4d6e87e.
// The cause: the stack router's navigation answered as the navigation of
// the shell's router did: with the future of the page it reached there,
// which ends with null as the shell closes.
// Steps: push the page with a result type, then navigate to it again, a
// frame later, then pop it with 7.
// Was: navigate got null at the pop.
// Should: navigate gets 7 at the pop, as push does. A navigation the guards
// there turn down still answers null at once. A navigate that names no page
// for a shell with no first page, or goes on into the tabs of a page
// already open, answers once it is done, as before: those pages, such as
// the tabs of an app's home, may never close, and going back to a screen
// already open gives no new result natively.
// Native behavior this holds to: Flutter's Navigator keeps the route of a
// page with the same type and key, as Page.canUpdate decides, and updates
// it with the new page, and Route.popped completes with the value given to
// Navigator.pop, so a caller holding that route's future gets the pop's
// result. popToViewController on iOS, onNewIntent on Android and popUntil
// in Flutter give no result of their own for a screen already open.
RootStackRouter _router({AutoRouteGuard? childGuard}) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
    ),
    NamedRouteDef(
      name: 'OtherRoute',
      path: '/other',
      builder: (_, _) => const Scaffold(body: Text('OtherRoute')),
    ),
    NamedRouteDef(
      name: 'ItemRoute',
      path: '/item/:id',
      builder: (_, data) =>
          Scaffold(body: Text('Item ${data.params.getString('id')}')),
    ),
    NamedRouteDef(
      name: 'ShellRoute',
      path: '/shell/:id',
      builder: (_, data) => Scaffold(
        body: Column(
          children: [
            Text('Shell ${data.params.getString('id')}'),
            const Expanded(child: AutoRouter()),
          ],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'XRoute',
          path: '',
          builder: (_, _) => const Text('XRoute'),
        ),
        NamedRouteDef(
          name: 'YRoute',
          path: 'y',
          guards: [?childGuard],
          builder: (_, _) => const Text('YRoute'),
        ),
        NamedRouteDef(
          name: 'InnerTabsRoute',
          path: 'tabs',
          builder: (_, _) => const AutoTabsRouter(
            routes: [
              NamedRoute<Object?>('InnerFeedTab'),
              NamedRoute<Object?>('InnerMailTab'),
            ],
          ),
          children: [
            NamedRouteDef(
              name: 'InnerFeedTab',
              path: 'feed',
              builder: (_, _) => const Text('InnerFeedTab'),
            ),
            NamedRouteDef(
              name: 'InnerMailTab',
              path: 'mail',
              builder: (_, _) => const Text('InnerMailTab'),
            ),
          ],
        ),
      ],
    ),
    NamedRouteDef(
      name: 'BareShellRoute',
      path: '/bare/:id',
      builder: (_, data) => Scaffold(
        body: Column(
          children: [
            Text('Bare ${data.params.getString('id')}'),
            const Expanded(child: AutoRouter()),
          ],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'ZRoute',
          path: 'z',
          builder: (_, _) => const Text('ZRoute'),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs/:id',
      builder: (_, data) => Scaffold(
        body: Column(
          children: [
            Text('Tabs ${data.params.getString('id')}'),
            const Expanded(
              child: AutoTabsRouter(
                routes: [
                  NamedRoute<Object?>('FeedTab'),
                  NamedRoute<Object?>('MailTab'),
                ],
              ),
            ),
          ],
        ),
      ),
      children: [
        NamedRouteDef(
          name: 'FeedTab',
          path: 'feed',
          builder: (_, _) => const Text('FeedTab'),
        ),
        NamedRouteDef(
          name: 'MailTab',
          path: 'mail',
          guards: [?childGuard],
          builder: (_, _) => const Text('MailTab'),
        ),
      ],
    ),
  ],
);

// What the code that called a navigation has heard so far.
class _Caller {
  new(this.name, Future<int?> future) {
    unawaited(
      future.then(
        (value) => result = value == null ? 'got null' : 'got $value',
      ),
    );
  }

  final String name;
  String result = 'waits';

  @override
  String toString() => '$name $result';
}

NamedRoute<Object?> _item(String id) => .new('ItemRoute', params: {'id': id});
NamedRoute<Object?> _shell(String id, [List<PageRouteInfo>? children]) =>
    .new('ShellRoute', params: {'id': id}, children: children);
NamedRoute<Object?> _tabs(String id, [List<PageRouteInfo>? children]) =>
    .new('TabsRoute', params: {'id': id}, children: children);

List<String> _names(StackRouter router) => [
  for (final page in router.stack) page.routeData.name,
];

void main() {
  // The page pushed first, the pages pushed over it, the navigation to it
  // again, and whether that navigation waits for the page's result.
  final cases =
      <String, (PageRouteInfo, List<PageRouteInfo>, PageRouteInfo, bool)>{
        'plain page, other params': (_item('1'), [], _item('2'), true),
        'plain page, same params': (_item('1'), [], _item('1'), true),
        'plain page under Other, other params': (
          _item('1'),
          [const NamedRoute('OtherRoute')],
          _item('2'),
          true,
        ),
        'shell, other params': (_shell('1'), [], _shell('2'), true),
        'shell, same params': (_shell('1'), [], _shell('1'), true),
        'shell, other params, child Y': (
          _shell('1'),
          [],
          _shell('2', const [NamedRoute('YRoute')]),
          true,
        ),
        'shell under Other, other params': (
          _shell('1'),
          [const NamedRoute('OtherRoute')],
          _shell('2'),
          true,
        ),
        'shell with no initial child, other params': (
          const NamedRoute('BareShellRoute', params: {'id': '1'}),
          [],
          const NamedRoute('BareShellRoute', params: {'id': '2'}),
          false,
        ),
        'tabs page, other params': (_tabs('1'), [], _tabs('2'), false),
        'tabs page, other params, other tab': (
          _tabs('1'),
          [],
          _tabs('2', const [NamedRoute('MailTab')]),
          false,
        ),
      };

  for (final MapEntry(key: name, value: (first, over, again, waits))
      in cases.entries) {
    testWidgets('navigate<int> to an open $name, then pop(7): '
        '${waits ? 'gets 7' : 'done at once'}', (tester) async {
      final router = _router();
      await pumpRouterApp(tester, router);
      final callers = [_Caller('push', router.push(first))];
      await tester.pumpAndSettle();
      for (final route in over) {
        unawaited(router.push(route));
        await tester.pumpAndSettle();
      }
      callers.add(_Caller('navigate', router.navigate(again)));
      await tester.pumpAndSettle();
      final beforePop = '$callers';
      router.pop(7);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_names(router), ['HomeRoute']);
      expect(
        (beforePop, '$callers'),
        waits
            ? ('[push waits, navigate waits]', '[push got 7, navigate got 7]')
            : (
                '[push waits, navigate got null]',
                '[push got 7, navigate got null]',
              ),
      );
    });
  }

  testWidgets('navigate<int> to an open shell and pop(7) in one turn', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    final callers = [_Caller('push', router.push<int>(_shell('1')))];
    await tester.pumpAndSettle();

    callers.add(_Caller('navigate', router.navigate<int>(_shell('2'))));
    router.pop(7);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_names(router), ['HomeRoute']);
    expect('$callers', '[push got 7, navigate got 7]');
  });

  for (final isTabs in [false, true]) {
    final where = isTabs ? 'a tab' : "the shell's router";
    for (final isLetIn in [true, false]) {
      testWidgets('navigate<int> to an open page, on into $where behind a '
          'guard that waits and ${isLetIn ? 'lets it in' : 'says no'}', (
        tester,
      ) async {
        final guard = HeldGuard();
        final router = _router(childGuard: guard);
        await pumpRouterApp(tester, router);
        final callers = [
          _Caller('push', router.push<int>(isTabs ? _tabs('1') : _shell('1'))),
        ];
        await tester.pumpAndSettle();

        callers.add(
          _Caller(
            'navigate',
            router.navigate<int>(
              isTabs
                  ? _tabs('2', const [NamedRoute('MailTab')])
                  : _shell('2', const [NamedRoute('YRoute')]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // What the callers have heard while the guard decides, once it has
        // answered, and after the pop.
        final heard = ['$callers'];
        isLetIn ? await guard.last.allow() : await guard.last.reject();
        await tester.pumpAndSettle();
        heard.add('$callers');
        router.pop(7);
        await tester.pumpAndSettle();
        heard.add('$callers');

        // Into the shell's stack the navigation gets the shell's result. Into
        // tabs it is done once the tab's guard has answered.
        expect(tester.takeException(), isNull);
        expect(
          heard,
          isLetIn && !isTabs
              ? [
                  '[push waits, navigate waits]',
                  '[push waits, navigate waits]',
                  '[push got 7, navigate got 7]',
                ]
              : [
                  '[push waits, navigate waits]',
                  '[push waits, navigate got null]',
                  '[push got 7, navigate got null]',
                ],
        );
      });
    }
  }

  // A link has no caller to answer, but it is let in as the navigation
  // reaches the page, not when the page closes: the dialog over the page
  // closes, as a link let in closes the dialogs over the page it reaches.
  // Also on into the tab on screen of tabs in the shell's stack.
  for (final link in [
    '/tabs/1/feed',
    '/tabs/1/mail',
    '/shell/1/y',
    '/shell/1/tabs/feed',
  ]) {
    testWidgets('A link to $link, through a page already open, closes the '
        'dialog over it', (tester) async {
      final router = _router();
      await pumpRouterApp(tester, router);
      final opened = switch (link) {
        '/shell/1/tabs/feed' => _shell('1', const [
          NamedRoute('InnerTabsRoute'),
        ]),
        _ when link.startsWith('/tabs') => _tabs('1'),
        _ => _shell('1'),
      };
      unawaited(router.push<int>(opened));
      await tester.pumpAndSettle();
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Draft')),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePushRoute(link);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Draft'), findsNothing);
      expect(router.currentUrl, link);
    });
  }

  testWidgets('control: navigate<int> to a shell not open, then pop(7)', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    final callers = [_Caller('navigate', router.navigate<int>(_shell('1')))];
    await tester.pumpAndSettle();
    expect('$callers', '[navigate waits]');

    router.pop(7);
    await tester.pumpAndSettle();

    expect('$callers', '[navigate got 7]');
  });
}
