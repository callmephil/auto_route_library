import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../build_counts.dart';
import '../router_test_utils.dart';

// A batch whose later route a guard rejects kept the pages its earlier routes
// had added, without telling the navigator. Found while fixing a rejected
// navigate to a page already open.
// Steps: open Home, then pushAll([First, Second]), where Second's guard
// rejects.
// Was: the stack was [Home, First] while Home showed at `/`, and the next
// change of the stack, such as a push and a pop, showed First, which nobody
// asked for. The same with popAndPushAll, navigatePath with
// includePrefixMatches, a link the platform hands the running app, and a
// guard's login page that is canceled.
// Should: a guard that rejects a route of a batch rejects the whole batch, as
// the upstream maintainer put it on #2299 and as replaceAll does: the stack,
// the screen and the url stay as they were. It holds to Flutter's Navigator,
// which takes a new list of pages as one update, to Android, which applies a
// fragment transaction as one atomic set of operations, and to the web, where
// a navigation the navigate event cancels leaves the url and the current
// entry as they were. A batch that begins on an empty stack, as when the app
// starts at a link, has nothing to go back to, so it keeps the pages its
// guards let through, as Android keeps the screens it puts under a linked
// screen.
enum _Guard { rejects, showsLogin, opensFallback }

_Guard _guard = .rejects;

final _secondGuard = AutoRouteGuard.simple((resolver, router) {
  switch (_guard) {
    case .rejects:
      resolver.reject();
    case .showsLogin:
      unawaited(
        resolver.redirectUntil(
          NamedRoute('LoginRoute', args: () => resolver.reject()),
        ),
      );
    case .opensFallback:
      resolver.reject();
      unawaited(router.push(const NamedRoute('FallbackRoute')));
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
  guards: [if (isGuarded) _secondGuard],
  keepHistory: keepHistory,
);

AutoRoute _child(String name, String path) => .new(
  page: PageInfo(
    name,
    builder: (data) =>
        Text('$name in shell ${data.inheritedPathParams.rawMap['id']}'),
  ),
  path: path,
);

RootStackRouter _buildRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('FirstRoute', '/first'),
    _page('SecondRoute', '/second', isGuarded: true),
    _page('ThirdRoute', '/third'),
    _page('FallbackRoute', '/fallback'),
    _page('NoticeRoute', '/notice', keepHistory: false),
    _page('ListRoute', '/list'),
    _page('CheckoutRoute', '/list/checkout', isGuarded: true),
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell/:id',
      keepHistory: false,
      children: [_child('ChildARoute', 'a'), _child('ChildBRoute', 'b')],
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

const List<PageRouteInfo> _firstAndSecond = [
  NamedRoute('FirstRoute'),
  NamedRoute('SecondRoute'),
];

Iterable<String?> _names(StackRouter router) => router.stack.map((p) => p.name);

void main() {
  late RootStackRouter router;

  setUp(() {
    _guard = .rejects;
    router = _buildRouter();
  });

  testWidgets('pushAll rejected by a later guard leaves the stack as it was', (
    tester,
  ) async {
    await pumpRouterApp(tester, router);

    unawaited(router.pushAll(_firstAndSecond));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expectTopPage(router, 'HomeRoute');
    expect(router.currentUrl, '/');

    unawaited(router.push(const NamedRoute('ThirdRoute')));
    await tester.pumpAndSettle();
    unawaited(router.maybePop());
    await tester.pumpAndSettle();

    expect(router.stack, hasLength(1));
    expectCurrentPage(router, 'HomeRoute');
    expect(find.text('FirstRoute'), findsNothing);
  });

  testWidgets('Canceling the login a later guard shows leaves the stack as '
      'it was', (tester) async {
    _guard = .showsLogin;
    await pumpRouterApp(tester, router);

    unawaited(router.pushAll(_firstAndSecond));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel login'));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expectTopPage(router, 'HomeRoute');
    expect(router.currentUrl, '/');
  });

  testWidgets('A page a guard opens as it rejects a batch stays, without the '
      "batch's pages", (tester) async {
    _guard = .opensFallback;
    await pumpRouterApp(tester, router);

    unawaited(router.pushAll(_firstAndSecond));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'FallbackRoute']);
    expectTopPage(router, 'FallbackRoute');
    expect(router.currentUrl, '/fallback');
  });

  testWidgets('A page that keeps no history stays when a batch over it is '
      'rejected', (tester) async {
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('NoticeRoute')));
    await tester.pumpAndSettle();

    unawaited(router.pushAll(_firstAndSecond));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'NoticeRoute']);
    expectTopPage(router, 'NoticeRoute');
    expect(router.currentUrl, '/notice');
  });

  // The batch's shell takes over the screen of the shell it takes off, with
  // its nested router; the router goes back to the shell put back.
  testWidgets('A shell that keeps no history comes back with its own nested '
      'router when a batch over it is rejected', (tester) async {
    await pumpRouterApp(tester, router);
    unawaited(
      router.push(
        const NamedRoute(
          'ShellRoute',
          params: {'id': 1},
          children: [NamedRoute('ChildARoute')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');

    unawaited(
      router.pushAll(const [
        NamedRoute('ShellRoute', params: {'id': 2}),
        NamedRoute('SecondRoute'),
      ]),
    );
    await tester.pumpAndSettle();
    unawaited(nested?.push(const NamedRoute('ChildBRoute')));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute', 'ShellRoute']);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(find.text('ChildBRoute in shell 1'), findsOneWidget);
    expect(router.currentUrl, '/shell/1/b');
  });

  // The pop is forced, as with popAndPush: it happens before the push.
  testWidgets('popAndPushAll rejected by a later guard keeps only its pop', (
    tester,
  ) async {
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('ThirdRoute')));
    await tester.pumpAndSettle();

    unawaited(router.popAndPushAll(_firstAndSecond));
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expectTopPage(router, 'HomeRoute');
    expect(router.currentUrl, '/');
  });

  testWidgets('navigatePath with prefix matches rejected by its last guard '
      'leaves the stack as it was', (tester) async {
    await pumpRouterApp(tester, router);

    unawaited(
      router.navigatePath('/list/checkout', includePrefixMatches: true),
    );
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expectTopPage(router, 'HomeRoute');
    expect(router.currentUrl, '/');
  });

  testWidgets('A link the running app gets, rejected by its last guard, '
      'leaves the stack and the url as they were', (tester) async {
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: true),
    );

    await tester.binding.handlePushRoute('/list/checkout');
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expectTopPage(router, 'HomeRoute');
    expect(router.currentUrl, '/');
  });

  // Documents the decision: going back to the empty stack would show nothing.
  testWidgets('An app that starts at a link its last guard rejects keeps the '
      'pages under it', (tester) async {
    await pumpAtDeepLink(
      tester,
      router,
      '/list/checkout',
      shouldIncludePrefixMatches: true,
    );

    expect(_names(router), ['HomeRoute', 'ListRoute']);
    expectTopPage(router, 'ListRoute');
  });
}
