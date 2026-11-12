import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// navigate to a page already open, whose guard now rejects, took that page
// and every page above it off the stack before the guard ran, and nothing put
// them back. Found while fixing replaceAll's kept shells.
// Steps: open Home, push Shell(id: 1, children: [ChildA]), push First, close
// the shell's guard, then navigate(Shell(id: 2, children: [ChildB])).
// Was: the stack was [Home] at `/` with Home shown; First and the shell were
// gone, ChildB went on in the gone shell's router, and a pop then left a
// blank screen. With a page holding no router, the stack lost the pages while
// they stayed on screen.
// Should: nothing changes, as with a rejected navigate to a page not open
// (blocked_link_keeps_stack_test.dart), replace (#2046) and replaceAll
// (#2299). It holds to native navigation: on the web, a traversal to an entry
// already in the history that the navigate event cancels leaves the url and
// the current entry as they were; on iOS an unwind segue no view controller
// takes leaves the current one on screen, and on iOS and macOS a segue that
// shouldPerformSegue stops isn't performed. Flutter's Router keeps building
// the current pages while its delegate decides, so a guard reads the stack on
// screen.
var _isOpen = true;
var _isLoginShown = false;
Completer<bool>? _decision;

final _guard = AutoRouteGuard.simple((resolver, _) async {
  if (_isLoginShown) {
    unawaited(
      resolver.redirectUntil(
        NamedRoute('LoginRoute', args: () => resolver.reject()),
      ),
    );
    return;
  }
  final decision = _decision;
  final isOpen = decision == null ? _isOpen : await decision.future;
  if (isOpen) {
    resolver.next();
  } else {
    resolver.reject();
  }
});

AutoRoute _page(String name, String path, {bool isGuarded = false}) => .new(
  page: PageInfo(name, builder: (_) => Scaffold(body: Text(name))),
  path: path,
  guards: [if (isGuarded) _guard],
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
    _page('GuardedRoute', '/guarded', isGuarded: true),
    _page('SecondRoute', '/second', isGuarded: true),
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
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell/:id',
      guards: [_guard],
      children: [
        _child('ChildARoute', 'a'),
        _child('ChildBRoute', 'b'),
        _child('ChildCRoute', 'c'),
      ],
    ),
  ],
);

NamedRoute<Object?> _shell(int id, String child) =>
    .new('ShellRoute', params: {'id': id}, children: [NamedRoute(child)]);

Iterable<String?> _names(StackRouter router) => router.stack.map((p) => p.name);

void main() {
  late RootStackRouter router;

  setUp(() {
    _isOpen = true;
    _isLoginShown = false;
    _decision = null;
    router = _buildRouter();
  });

  // Opens [Home, Shell(id: 1, children: [ChildA]), First] and returns the
  // shell's nested router.
  Future<StackRouter?> openShellUnderFirst(WidgetTester tester) async {
    await pumpRouterApp(tester, router);
    unawaited(router.push(_shell(1, 'ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(const NamedRoute('FirstRoute')));
    await tester.pumpAndSettle();
    return nested;
  }

  testWidgets(
    'navigate to a shell already open that its guard now rejects leaves '
    'the stack, the url and the shell as they were',
    (tester) async {
      final nested = await openShellUnderFirst(tester);

      _isOpen = false;
      unawaited(router.navigate(_shell(2, 'ChildBRoute')));
      await tester.pumpAndSettle();

      expect(_names(router), ['HomeRoute', 'ShellRoute', 'FirstRoute']);
      expect(router.currentUrl, '/first');
      expect(find.text('FirstRoute'), findsOneWidget);
      expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
      expect(_names(nested!), ['ChildARoute']);

      router.pop();
      await tester.pumpAndSettle();

      expect(_names(router), ['HomeRoute', 'ShellRoute']);
      expect(router.currentUrl, '/shell/1/a');
      expect(find.text('ChildARoute in shell 1'), findsOneWidget);
    },
  );

  testWidgets(
    'after the rejected navigate, a later page of the same route leaves '
    "the shell's router to the shell",
    (tester) async {
      final nested = await openShellUnderFirst(tester);
      _isOpen = false;
      unawaited(router.navigate(_shell(2, 'ChildBRoute')));
      await tester.pumpAndSettle();

      _isOpen = true;
      unawaited(router.push(_shell(3, 'ChildCRoute')));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      unawaited(nested!.push(const NamedRoute('ChildBRoute')));
      await tester.pumpAndSettle();

      expect(_names(router), ['HomeRoute', 'ShellRoute']);
      expect(find.text('ChildBRoute in shell 1'), findsOneWidget);
      expect(router.currentUrl, '/shell/1/b');
    },
  );

  final reachAgain = {
    'navigate': () => router.navigate(const NamedRoute('GuardedRoute')),
    'navigatePath': () => router.navigatePath('/guarded'),
  };
  for (final MapEntry(:key, :value) in reachAgain.entries) {
    testWidgets(
      '$key to a page already open that its guard now rejects keeps it and '
      'the pages above it',
      (tester) async {
        await pumpRouterApp(tester, router);
        unawaited(router.push(const NamedRoute('GuardedRoute')));
        await tester.pumpAndSettle();
        unawaited(router.push(const NamedRoute('FirstRoute')));
        await tester.pumpAndSettle();

        _isOpen = false;
        unawaited(value());
        await tester.pumpAndSettle();

        expect(_names(router), ['HomeRoute', 'GuardedRoute', 'FirstRoute']);
        expect(router.currentUrl, '/first');
        expect(find.text('FirstRoute'), findsOneWidget);

        router.pop();
        await tester.pumpAndSettle();

        expect(_names(router), ['HomeRoute', 'GuardedRoute']);
        expect(find.text('GuardedRoute'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'while the guard of a shell already open decides, the stack is the one '
    'on screen, and stays so when it rejects',
    (tester) async {
      await openShellUnderFirst(tester);
      final decision = Completer<bool>();
      _decision = decision;

      unawaited(router.navigate(_shell(2, 'ChildBRoute')));
      await tester.pumpAndSettle();

      final stackWhileDeciding = _names(router).join(', ');
      final firstShownWhileDeciding = find.text('FirstRoute').evaluate().length;
      decision.complete(false);
      await tester.pumpAndSettle();

      const stack = 'HomeRoute, ShellRoute, FirstRoute';
      expect((stackWhileDeciding, _names(router).join(', ')), (stack, stack));
      expect(
        (firstShownWhileDeciding, find.text('FirstRoute').evaluate().length),
        (1, 1),
      );
      expect(router.currentUrl, '/first');
    },
  );

  testWidgets(
    'canceling the login that the guard of a shell already open shows leaves '
    'the stack as it was, with the shell built once',
    (tester) async {
      final nested = await openShellUnderFirst(tester);

      _isLoginShown = true;
      unawaited(router.navigate(_shell(2, 'ChildBRoute')));
      await tester.pumpAndSettle();

      expect(_names(router), [
        'HomeRoute',
        'ShellRoute',
        'FirstRoute',
        'LoginRoute',
      ]);

      await tester.tap(find.text('Cancel login'));
      await tester.pumpAndSettle();

      expect(_names(router), ['HomeRoute', 'ShellRoute', 'FirstRoute']);
      expect(router.currentUrl, '/first');
      expect(find.text('FirstRoute'), findsOneWidget);
      expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
      expect(_names(nested!), ['ChildARoute']);
    },
  );

  testWidgets(
    'a link that keeps the pages under its route, which a guard rejects, '
    'keeps the pages above them',
    (tester) async {
      await pumpRouterApp(tester, router);
      unawaited(router.push(const NamedRoute('FirstRoute')));
      await tester.pumpAndSettle();

      _isOpen = false;
      unawaited(router.navigatePath('/second', includePrefixMatches: true));
      await tester.pumpAndSettle();

      expect(_names(router), ['HomeRoute', 'FirstRoute']);
      expect(router.currentUrl, '/first');
      expect(find.text('FirstRoute'), findsOneWidget);
    },
  );
}
