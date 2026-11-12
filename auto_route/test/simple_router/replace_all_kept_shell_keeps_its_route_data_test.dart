import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The nested router of a shell replaceAll keeps below the top belongs to the
// page that keeps the shell, and to no other page of the shell's route.
// Flutter's Navigator hands a route it shows, with the nested Navigator built
// inside it, only to the new page with the same key, and builds a new route
// for a page with a new key (Navigator._updatePages); a navigation a guard
// rejects never reaches it. UIKit's setViewControllers keeps the view
// controller instances in both arrays, each with its own children, and
// Android's Navigation gives each back stack entry its own arguments.

// Whether GuardedRoute's guard lets it in.
var _isGuardOpen = true;

class _FlagGuard extends AutoRouteGuard {
  const new();

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (_isGuardOpen) {
      resolver.next();
    } else {
      resolver.reject();
    }
  }
}

// Shows its name and the shell id it inherits from its parents.
class _Child extends StatelessWidget {
  const new(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final id = RouteData.of(context).inheritedPathParams.getString('id');
    return Text('$name in shell $id');
  }
}

AutoRoute _page(
  String name,
  String path, {
  List<AutoRouteGuard> guards = const [],
}) => .new(
  page: PageInfo(name, builder: (_) => Text(name)),
  path: path,
  guards: guards,
);

AutoRoute _child(String name, String path) => .new(
  page: PageInfo(name, builder: (_) => _Child(name)),
  path: path,
);

RootStackRouter _buildRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('FirstRoute', '/first'),
    _page('SecondRoute', '/second'),
    _page('GuardedRoute', '/guarded', guards: const [_FlagGuard()]),
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell/:id',
      children: [
        _child('ChildARoute', 'a'),
        _child('ChildBRoute', 'b'),
        _child('ChildCRoute', 'c'),
      ],
    ),
  ],
);

const NamedRoute<Object?> _home = NamedRoute('HomeRoute');
const NamedRoute<Object?> _first = NamedRoute('FirstRoute');
const NamedRoute<Object?> _second = NamedRoute('SecondRoute');
const NamedRoute<Object?> _guarded = NamedRoute('GuardedRoute');

NamedRoute<Object?> _shell(int id, String child) =>
    .new('ShellRoute', params: {'id': id}, children: [NamedRoute(child)]);

void main() {
  setUp(() => _isGuardOpen = true);

  // Steps: push GuardedRoute, ShellRoute 1 showing ChildARoute, and
  // FirstRoute. With GuardedRoute's guard closed, call replaceAll with
  // HomeRoute, GuardedRoute, ShellRoute 2 showing ChildBRoute, and
  // SecondRoute. Open the guard, push ShellRoute 3 showing ChildCRoute, pop
  // it and FirstRoute, then push ChildBRoute in shell 1.
  // Happened: shell 1's nested router had the route data of the popped
  // ShellRoute 3 page, so ChildBRoute showed shell 3's id.
  // Should: the router keeps shell 1's page data, and ChildBRoute shows
  // shell 1's id.
  testWidgets('A replaceAll a guard rejects leaves no later page of the '
      "route a kept shell's nested router", (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_guarded));
    await tester.pumpAndSettle();
    unawaited(router.push(_shell(1, 'ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    _isGuardOpen = false;
    unawaited(
      router.replaceAll([_home, _guarded, _shell(2, 'ChildBRoute'), _second]),
    );
    await tester.pumpAndSettle();
    _isGuardOpen = true;
    unawaited(router.push(_shell(3, 'ChildCRoute')));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    unawaited(nested?.push(const NamedRoute('ChildBRoute')));
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.name), [
      'HomeRoute',
      'GuardedRoute',
      'ShellRoute',
    ]);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(find.text('ChildBRoute in shell 1'), findsOneWidget);
    expect(router.currentUrl, '/shell/1/b');
    final shellData = router.stack.lastOrNull?.routeData;
    expect(nested?.routeData, allOf(isNotNull, same(shellData)));
    expect(
      nested?.stack.firstOrNull?.routeData.parent,
      allOf(isNotNull, same(shellData)),
    );
  });

  // Steps: push FirstRoute, ShellRoute 1 showing ChildARoute, and
  // SecondRoute, then call replaceAll with HomeRoute, ShellRoute 2 showing
  // ChildCRoute, FirstRoute, ShellRoute 3 showing ChildBRoute, and
  // SecondRoute, and pop.
  // Happened: ShellRoute 3 keeps shell 1's screen, but the screen's nested
  // router took ShellRoute 2's route data, so ChildBRoute showed shell 2's
  // id at /shell/3/b.
  // Should: the router has ShellRoute 3's data, and ChildBRoute shows
  // shell 3's id.
  testWidgets("An earlier page of a kept shell's route in the same "
      "replaceAll doesn't take the shell's nested router", (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_first));
    await tester.pumpAndSettle();
    unawaited(router.push(_shell(1, 'ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(_second));
    await tester.pumpAndSettle();

    unawaited(
      router.replaceAll([
        _home,
        _shell(2, 'ChildCRoute'),
        _first,
        _shell(3, 'ChildBRoute'),
        _second,
      ]),
    );
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.name), [
      'HomeRoute',
      'ShellRoute',
      'FirstRoute',
      'ShellRoute',
    ]);
    expect(nested?.stack.map((page) => page.name), ['ChildBRoute']);
    expect(find.text('ChildBRoute in shell 3'), findsOneWidget);
    expect(router.currentUrl, '/shell/3/b');
    final shellData = router.stack.lastOrNull?.routeData;
    expect(nested?.routeData, allOf(isNotNull, same(shellData)));
    expect(
      nested?.stack.singleOrNull?.routeData.parent,
      allOf(isNotNull, same(shellData)),
    );
  });
}
