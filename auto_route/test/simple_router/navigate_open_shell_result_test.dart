import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// What navigate answers, and when, for a page already open. It answers as
// the innermost page it reaches answers, when that page closes, with that
// page's result: for a plain page that is the page itself; for a page that
// holds a stack of its own, a shell, the page the navigation reaches inside
// it, so an await on a shell that never closes, such as the app's home,
// goes on once that inner page closes. A navigation that names no page for
// a shell with no first page, and one into tabs, answer once they are done.
// Kept as the owner decided after the review of the batch: a change that
// made a shell answer with its own result never completed an await on a
// home shell.
// Native behavior this holds to: going back to a screen that is already
// open gives no result of its own (popToViewController on iOS, onNewIntent
// on Android, popUntil in Flutter); a page a navigation shows answers when
// it closes, as Route.popped completes with the value given to
// Navigator.pop.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
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
          builder: (_, _) => const Text('YRoute'),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'BareShellRoute',
      path: '/bare/:id',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
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
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('FeedTab'),
            NamedRoute<Object?>('MailTab'),
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
          builder: (_, _) => const Text('MailTab'),
        ),
      ],
    ),
  ],
);

// The app's home is a shell at '/' with Dashboard and Settings in its stack.
RootStackRouter _appShellRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'AppShellRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'DashboardRoute',
          path: '',
          builder: (_, _) => const Text('DashboardRoute'),
        ),
        NamedRouteDef(
          name: 'SettingsRoute',
          path: 'settings',
          builder: (_, _) => const Text('SettingsRoute'),
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

void main() {
  // The page pushed first, the navigation to it again, and what the
  // navigation has heard before the pop and after pop(7) closes the page.
  final cases = <String, (PageRouteInfo, PageRouteInfo, String, String)>{
    'a plain page: its own result': (
      _item('1'),
      _item('2'),
      'navigate waits',
      'navigate got 7',
    ),
    'a shell with pages: the page it reaches inside, closed with the shell': (
      _shell('1'),
      _shell('2'),
      'navigate waits',
      'navigate got null',
    ),
    'a shell with no first page: done at once': (
      const NamedRoute('BareShellRoute', params: {'id': '1'}),
      const NamedRoute('BareShellRoute', params: {'id': '2'}),
      'navigate got null',
      'navigate got null',
    ),
    'a tabs page: done at once': (
      const NamedRoute('TabsRoute', params: {'id': '1'}),
      const NamedRoute(
        'TabsRoute',
        params: {'id': '2'},
        children: [NamedRoute('MailTab')],
      ),
      'navigate got null',
      'navigate got null',
    ),
  };

  for (final MapEntry(key: name, value: (first, again, before, after))
      in cases.entries) {
    testWidgets('navigate<int> to an open page answers as $name', (
      tester,
    ) async {
      final router = _router();
      await pumpRouterApp(tester, router);
      unawaited(router.push<int>(first));
      await tester.pumpAndSettle();
      final caller = _Caller('navigate', router.navigate(again));
      await tester.pumpAndSettle();
      final heard = ['$caller'];
      router.pop(7);
      await tester.pumpAndSettle();
      heard.add('$caller');

      expect(tester.takeException(), isNull);
      expect(heard, [before, after]);
    });
  }

  testWidgets('navigate<int> into an open shell answers with the result of '
      'the page it reaches inside, when that page closes', (tester) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    unawaited(router.push<int>(_shell('1')));
    await tester.pumpAndSettle();
    final caller = _Caller(
      'navigate',
      router.navigate(_shell('1', const [NamedRoute('YRoute')])),
    );
    await tester.pumpAndSettle();
    final heard = ['$caller'];

    router.innerRouterOf<StackRouter>('ShellRoute')!.pop(5);
    await tester.pumpAndSettle();
    heard.add('$caller');

    expect(tester.takeException(), isNull);
    expect(heard, ['navigate waits', 'navigate got 5']);
  });

  testWidgets("An await on navigate into the stack of the app's home shell "
      'goes on once the page it opened there closes', (tester) async {
    final router = _appShellRouter();
    await pumpRouterApp(tester, router);
    final caller = _Caller(
      'navigate',
      router.navigate(
        const NamedRoute(
          'AppShellRoute',
          children: [NamedRoute('SettingsRoute')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final heard = ['$caller ${router.currentUrl}'];

    router.back();
    await tester.pumpAndSettle();
    heard.add('$caller ${router.currentUrl}');

    expect(tester.takeException(), isNull);
    expect(heard, ['navigate waits /settings', 'navigate got null /']);
  });
}
