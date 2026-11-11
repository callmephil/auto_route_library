import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A shell whose screen replaceAll keeps below the top, as the new stack has a
// page of its route at its place, shows the children replaceAll names for it,
// as a shell built anew does. Flutter's Navigator, run with keyless pages,
// updates such a page's route in place: the page keeps its state and builds
// its new content, so a nested Navigator in it shows the new page's children.
// SwiftUI's NavigationStack keeps the state of a screen whose place in the
// path stays and hands it the new value through onChange, and Android hands
// a single-top activity the new intent: a kept screen keeps its state and
// takes its new input.

// How many times each screen's state was created.
final _created = <String, int>{};

class _Screen extends StatefulWidget {
  const new(this.name);

  final String name;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  late final int _number = _created.update(
    widget.name,
    (count) => count + 1,
    ifAbsent: () => 1,
  );

  @override
  Widget build(BuildContext context) => Text('${widget.name} #$_number');
}

// A guard that lets its route in, or keeps it out, once the test decides.
class _HeldGuard extends AutoRouteGuard {
  final decision = Completer<bool>();

  @override
  Future<void> onNavigation(
    NavigationResolver resolver,
    StackRouter router,
  ) async {
    if (await decision.future) {
      resolver.next();
    } else {
      resolver.reject();
    }
  }
}

AutoRoute _page(
  String name,
  String path, {
  List<AutoRouteGuard> guards = const [],
}) => .new(
  page: PageInfo(name, builder: (_) => _Screen(name)),
  path: path,
  guards: guards,
);

RootStackRouter _buildRouter({_HeldGuard? guard}) => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('FirstRoute', '/first'),
    _page('SecondRoute', '/second'),
    _page('GuardedRoute', '/guarded', guards: [?guard]),
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell',
      children: [_page('ChildARoute', 'a'), _page('ChildBRoute', 'b')],
    ),
    AutoRoute(
      page: PageInfo(
        'TabsRoute',
        builder: (_) => const AutoTabsRouter(
          routes: [NamedRoute('TabARoute'), NamedRoute('TabBRoute')],
        ),
      ),
      path: '/tabs',
      children: [_page('TabARoute', 'a'), _page('TabBRoute', 'b')],
    ),
  ],
);

const NamedRoute<Object?> _home = NamedRoute('HomeRoute');
const NamedRoute<Object?> _first = NamedRoute('FirstRoute');
const NamedRoute<Object?> _second = NamedRoute('SecondRoute');
const NamedRoute<Object?> _guarded = NamedRoute('GuardedRoute');

NamedRoute<Object?> _shell(String child) =>
    .new('ShellRoute', children: [NamedRoute(child)]);

NamedRoute<Object?> _tabs(String child) =>
    .new('TabsRoute', children: [NamedRoute(child)]);

// Pushes ShellRoute showing ChildARoute and FirstRoute over it, then calls
// replaceAll with HomeRoute, ShellRoute showing ChildBRoute, and GuardedRoute,
// whose [guard] decides. Returns the shell's nested router.
Future<StackRouter?> _replaceAllBehindGuard(
  WidgetTester tester,
  RootStackRouter router,
) async {
  await pumpRouterApp(tester, router);
  unawaited(router.push(_shell('ChildARoute')));
  await tester.pumpAndSettle();
  final nested = router.innerRouterOf<StackRouter>('ShellRoute');
  unawaited(router.push(_first));
  await tester.pumpAndSettle();
  unawaited(router.replaceAll([_home, _shell('ChildBRoute'), _guarded]));
  await tester.pumpAndSettle();
  return nested;
}

void main() {
  setUp(_created.clear);

  // Steps: push ShellRoute showing ChildARoute, push FirstRoute, replaceAll
  // with HomeRoute, ShellRoute showing ChildBRoute, and SecondRoute, then
  // pop.
  // Happened: the shell kept its screen but still showed ChildARoute, at
  // /shell/a; before 12.6.0's fix for kept screens, the url said /shell/b.
  // Should: the shell keeps its nested router, which shows ChildBRoute at
  // /shell/b.
  testWidgets('A shell that replaceAll keeps below the top shows the child '
      'replaceAll names', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_shell('ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _shell('ChildBRoute'), _second]));
    await tester.pumpAndSettle();
    expect(find.text('SecondRoute #1'), findsOneWidget);
    expect(router.currentUrl, '/second');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('ChildBRoute #1'), findsOneWidget);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(nested?.stack.map((page) => page.name), ['ChildBRoute']);
    expect(router.currentUrl, '/shell/b');
  });

  // Steps: push ShellRoute showing ChildARoute, push FirstRoute, and call
  // replaceAll with HomeRoute and ShellRoute showing ChildBRoute.
  // Happened: the shell's nested router put ChildBRoute on top of ChildARoute
  // the way navigate opens a child.
  // Should: the shell shows ChildBRoute alone, as on top or when built anew.
  testWidgets('A shell that replaceAll keeps as its last page shows only the '
      'child replaceAll names', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_shell('ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _shell('ChildBRoute')]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ChildBRoute #1'), findsOneWidget);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(nested?.stack.map((page) => page.name), ['ChildBRoute']);
    expect(router.currentUrl, '/shell/b');
  });

  // Steps: push TabsRoute on TabARoute, push FirstRoute, replaceAll with
  // HomeRoute, TabsRoute on TabBRoute, and SecondRoute, then pop.
  // Happened: the tabs kept their screen but still showed TabARoute.
  // Should: the tabs keep their router and their tab states, and show
  // TabBRoute at /tabs/b.
  testWidgets('Tabs that replaceAll keeps below the top show the tab '
      'replaceAll names', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_tabs('TabARoute')));
    await tester.pumpAndSettle();
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute');
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _tabs('TabBRoute'), _second]));
    await tester.pumpAndSettle();

    router.pop();
    await tester.pumpAndSettle();
    expect(router.innerRouterOf<TabsRouter>('TabsRoute'), same(tabs));
    expect(tabs?.activeIndex, 1);
    expect(find.text('TabBRoute #1'), findsOneWidget);
    expect(_created['TabARoute'], 1);
    expect(router.currentUrl, '/tabs/b');
  });

  // Steps: push ShellRoute showing ChildARoute and FirstRoute, call
  // replaceAll with HomeRoute, ShellRoute showing ChildBRoute, and
  // GuardedRoute, whose guard rejects it, then pop.
  // Should: the whole batch is rejected and the stack restored, so the shell
  // still shows ChildARoute, with its state, at /shell/a.
  testWidgets('A replaceAll a guard rejects leaves a shell it would keep '
      'below the top on its children', (tester) async {
    final guard = _HeldGuard()..decision.complete(false);
    final router = _buildRouter(guard: guard);
    final nested = await _replaceAllBehindGuard(tester, router);
    expect(find.text('FirstRoute #1'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('ChildARoute #1'), findsOneWidget);
    expect(nested?.stack.map((page) => page.name), ['ChildARoute']);
    expect(router.currentUrl, '/shell/a');
  });

  // Steps: push ShellRoute showing ChildARoute and FirstRoute, call
  // replaceAll with HomeRoute, ShellRoute showing ChildBRoute, and
  // GuardedRoute, whose guard takes its time, let it in, then pop.
  // Should: while the guard decides, FirstRoute stays on screen and the
  // shell keeps ChildARoute; once it lets GuardedRoute in, the shell shows
  // ChildBRoute.
  testWidgets('A shell replaceAll keeps below the top shows the new child '
      'only once a guard lets the batch in', (tester) async {
    final guard = _HeldGuard();
    final router = _buildRouter(guard: guard);
    final nested = await _replaceAllBehindGuard(tester, router);
    expect(find.text('FirstRoute #1'), findsOneWidget);
    final whileDeciding = nested?.stack.map((page) => page.name).toList();

    guard.decision.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('GuardedRoute #1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(whileDeciding, ['ChildARoute']);
    expect(find.text('ChildBRoute #1'), findsOneWidget);
    expect(nested?.stack.map((page) => page.name), ['ChildBRoute']);
    expect(router.currentUrl, '/shell/b');
  });

  // Steps: push ShellRoute showing ChildARoute and FirstRoute, call
  // replaceAll with HomeRoute, ShellRoute showing ChildBRoute, and
  // GuardedRoute, whose guard takes its time and then rejects it, then pop.
  // Should: FirstRoute stays on screen with its state throughout, and the
  // shell still shows ChildARoute.
  testWidgets('A guard that takes its time and rejects a replaceAll leaves '
      'the screens as they were', (tester) async {
    final guard = _HeldGuard();
    final router = _buildRouter(guard: guard);
    final nested = await _replaceAllBehindGuard(tester, router);
    final firstWhileDeciding = find.text('FirstRoute #1').evaluate().length;

    guard.decision.complete(false);
    await tester.pumpAndSettle();
    expect(
      (firstWhileDeciding, find.text('FirstRoute #1').evaluate().length),
      (1, 1),
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('ChildARoute #1'), findsOneWidget);
    expect(nested?.stack.map((page) => page.name), ['ChildARoute']);
    expect(router.currentUrl, '/shell/a');
  });
}
