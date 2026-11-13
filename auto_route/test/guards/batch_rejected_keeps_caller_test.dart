import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A batch a later guard rejects put back a page its first route had taken
// off, but the code that opened that page had already been told it closed.
// Found while fixing a batch a later guard rejects (50534c5d).
// Steps: open Home, push<int> Notice, a page that keeps no history, and wait
// for its result. Then pushAll([First, Second]), where Second's guard
// rejects.
// Was: Notice came back on screen, but the push that opened it had already
// finished with null, as if Notice had closed: First's page took Notice off
// and answered its caller at once, before Second's guard decided. A pop of
// Notice with a result then reached nobody. The same happened to the page
// replacePath replaces when a later route of the path is rejected, and to the
// pages above the target that a link takes off when the user cancels the
// login a later guard shows.
// Should: a page a batch takes off answers its caller only once the batch is
// in. A rejected batch puts the page back with its caller still waiting, and
// a pop with a result reaches it. It holds to Flutter's Navigator, which
// completes a route's popped future only when it applies a list of pages
// without that route (_RouteEntry.handleComplete from _updatePages), so a
// change it never applies leaves the route and its future alone; to the web,
// where a navigation the navigate event cancels leaves the current entry
// without firing its dispose event; and to Android, where a fragment
// transaction is applied as one atomic set of operations, so a transaction
// never committed leaves every fragment and its result listener in place.
enum _Guard { rejects, showsLogin }

_Guard _guard = .rejects;

final _laterGuard = AutoRouteGuard.simple((resolver, _) {
  switch (_guard) {
    case .rejects:
      resolver.reject();
    case .showsLogin:
      unawaited(
        resolver.redirectUntil(
          NamedRoute('LoginRoute', args: () => resolver.reject()),
        ),
      );
  }
});

AutoRoute _page(
  String name,
  String path, {
  bool isGuarded = false,
  bool keepHistory = true,
}) => .new(
  page: PageInfo(name, builder: (_) => Scaffold(body: Text(name))),
  path: path,
  guards: [if (isGuarded) _laterGuard],
  keepHistory: keepHistory,
);

RootStackRouter _buildRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('FirstRoute', '/first'),
    _page('SecondRoute', '/second', isGuarded: true),
    _page('ThirdRoute', '/third'),
    _page('NoticeRoute', '/notice', keepHistory: false),
    _page('ListRoute', '/list'),
    _page('CheckoutRoute', '/list/checkout', isGuarded: true),
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell/:id',
      keepHistory: false,
      children: [
        AutoRoute(
          page: PageInfo(
            'ChildRoute',
            builder: (data) => Text(
              'ChildRoute in shell ${data.inheritedPathParams.rawMap['id']}',
            ),
          ),
          path: '',
        ),
      ],
    ),
    AutoRoute(
      page: PageInfo(
        'LoginRoute',
        builder: (data) => Scaffold(
          body: TextButton(
            onPressed: data.args! as VoidCallback,
            child: const Text('Cancel login'),
          ),
        ),
      ),
      path: '/login',
    ),
  ],
);

// The result the push of a page gets, once it gets one.
class _Caller {
  bool isAnswered = false;
  int? result;

  void wait(Future<int?> popped) {
    unawaited(
      popped.then((value) {
        isAnswered = true;
        result = value;
      }),
    );
  }
}

Iterable<String?> _names(StackRouter router) => router.stack.map((p) => p.name);

void main() {
  late RootStackRouter router;
  late _Caller caller;

  setUp(() {
    _guard = .rejects;
    router = _buildRouter();
    caller = _Caller();
  });

  Future<void> openAndWait(
    WidgetTester tester,
    String name, {
    Map<String, Object?> params = const {},
  }) async {
    await pumpRouterApp(tester, router);
    caller.wait(router.push<int>(NamedRoute(name, params: params)));
    await tester.pumpAndSettle();
  }

  Future<void> cancelLogin(WidgetTester tester) async {
    expect(router.topRoute.name, 'LoginRoute');
    await tester.tap(find.text('Cancel login'));
    await tester.pumpAndSettle();
  }

  // The page is back on top, its caller still waits, and a pop with a result
  // reaches it.
  Future<void> expectCallerWaits(WidgetTester tester, String name) async {
    expectTopPage(router, name);
    expect(caller.isAnswered, isFalse);

    unawaited(router.maybePop(7));
    await tester.pumpAndSettle();

    expect(caller.isAnswered, isTrue);
    expect(caller.result, 7);
  }

  testWidgets('A page that keeps no history, put back by a rejected batch, '
      'keeps its caller waiting', (tester) async {
    await openAndWait(tester, 'NoticeRoute');

    unawaited(
      router.pushAll(const [
        NamedRoute('FirstRoute'),
        NamedRoute('SecondRoute'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'NoticeRoute']);
    await expectCallerWaits(tester, 'NoticeRoute');
  });

  testWidgets('A page that keeps no history keeps its caller waiting when '
      'the login of a later guard is canceled', (tester) async {
    _guard = .showsLogin;
    await openAndWait(tester, 'NoticeRoute');

    unawaited(
      router.pushAll(const [
        NamedRoute('FirstRoute'),
        NamedRoute('SecondRoute'),
      ]),
    );
    await tester.pumpAndSettle();
    await cancelLogin(tester);

    expect(_names(router), ['HomeRoute', 'NoticeRoute']);
    await expectCallerWaits(tester, 'NoticeRoute');
  });

  // The batch's shell takes over the screen of the shell it takes off, with
  // the wait of its caller; the wait goes back with the shell put back.
  testWidgets('A shell that keeps no history, put back by a rejected batch, '
      'keeps its caller waiting', (tester) async {
    await openAndWait(tester, 'ShellRoute', params: {'id': 1});

    unawaited(
      router.pushAll(const [
        NamedRoute('ShellRoute', params: {'id': 2}),
        NamedRoute('SecondRoute'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'ShellRoute']);
    expect(find.text('ChildRoute in shell 1'), findsOneWidget);
    expect(router.topRoute.name, 'ChildRoute');
    expect(caller.isAnswered, isFalse);

    unawaited(router.maybePop(7));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expect(caller.result, 7);
  });

  testWidgets('The page replacePath would replace keeps its caller waiting '
      'when a later route of the path is rejected', (tester) async {
    await openAndWait(tester, 'ThirdRoute');

    unawaited(router.replacePath('/list/checkout', includePrefixMatches: true));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'ThirdRoute']);
    await expectCallerWaits(tester, 'ThirdRoute');
  });

  testWidgets('A page a link takes off keeps its caller waiting when the '
      'login of a later guard is canceled', (tester) async {
    _guard = .showsLogin;
    await openAndWait(tester, 'ThirdRoute');

    unawaited(
      router.navigatePath('/list/checkout', includePrefixMatches: true),
    );
    await tester.pumpAndSettle();
    await cancelLogin(tester);

    expect(_names(router), ['HomeRoute', 'ThirdRoute']);
    await expectCallerWaits(tester, 'ThirdRoute');
  });

  // The page left for good, so its caller is answered, as Flutter completes
  // a removed route's future, and the call waiting on it lets go of the pages
  // it holds.
  testWidgets('A page that keeps no history answers its caller with null '
      'once the batch over it is in', (tester) async {
    await openAndWait(tester, 'NoticeRoute');

    unawaited(
      router.pushAll(const [
        NamedRoute('FirstRoute'),
        NamedRoute('ThirdRoute'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'FirstRoute', 'ThirdRoute']);
    expect(caller.isAnswered, isTrue);
    expect(caller.result, isNull);
  });
}
