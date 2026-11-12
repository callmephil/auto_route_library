import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A replaceAll that keeps the shell on top changes the shell's children only
// once every guard of the batch has let it in. Flutter's Router keeps
// building the current configuration while RouterDelegate.setNewRoutePath
// waits, and rebuilds once it completes, so a navigation that is still being
// decided changes nothing on screen; its Navigator then takes the new pages,
// with the nested Navigator built from a page's config, in one update. The
// replaceAll docs promise the same for a guard that rejects: the whole batch
// is rejected and the stack restored.

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

RootStackRouter _buildRouter(_HeldGuard guard) => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('FirstRoute', '/first'),
    _page('GuardedRoute', '/guarded', guards: [guard]),
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell',
      children: [_page('ChildARoute', 'a'), _page('ChildBRoute', 'b')],
    ),
  ],
);

const NamedRoute<Object?> _home = NamedRoute('HomeRoute');
const NamedRoute<Object?> _first = NamedRoute('FirstRoute');
const NamedRoute<Object?> _guarded = NamedRoute('GuardedRoute');

NamedRoute<Object?> _shell(String child) =>
    .new('ShellRoute', children: [NamedRoute(child)]);

// The urls the router sends the platform from now on, with whether each one
// replaces the current history entry.
List<(String, bool)> _recordSentUrls(WidgetTester tester) {
  final sent = <(String, bool)>[];
  final messenger = tester.binding.defaultBinaryMessenger
    // reason: Intended to be null, because the handler is only for routeInformationUpdated, which returns null.
    // ignore: function-always-returns-null
    ..setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        final arguments = call.arguments as Map;
        sent.add((arguments['uri'] as String, arguments['replace'] == true));
      }
      return null;
    });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.navigation, null),
  );
  return sent;
}

// Pushes ShellRoute showing ChildARoute, then calls replaceAll with HomeRoute,
// ShellRoute showing ChildBRoute, and GuardedRoute, whose guard decides when
// the test says. Returns the shell's nested router.
Future<StackRouter?> _replaceAllOverShell(
  WidgetTester tester,
  RootStackRouter router,
) async {
  await pumpRouterApp(tester, router);
  unawaited(router.push(_shell('ChildARoute')));
  await tester.pumpAndSettle();
  final nested = router.innerRouterOf<StackRouter>('ShellRoute');
  unawaited(router.replaceAll([_home, _shell('ChildBRoute'), _guarded]));
  await tester.pumpAndSettle();
  return nested;
}

void main() {
  setUp(_created.clear);

  // Steps: push ShellRoute showing ChildARoute, then call replaceAll with
  // HomeRoute, ShellRoute showing ChildBRoute, and GuardedRoute, whose guard
  // rejects it.
  // Happened: the root stack was restored, but the shell showed ChildBRoute
  // at /shell/b, and ChildARoute's state was gone.
  // Should: the shell shows ChildARoute, with its state, at /shell/a, and its
  // nested router belongs to the shell's page again.
  testWidgets('A replaceAll a guard rejects leaves the shell on top on its '
      'children', (tester) async {
    final guard = _HeldGuard()..decision.complete(false);
    final router = _buildRouter(guard);
    final nested = await _replaceAllOverShell(tester, router);

    expect(find.text('ChildARoute #1'), findsOneWidget);
    expect(router.stack.map((page) => page.name), ['HomeRoute', 'ShellRoute']);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(nested?.stack.map((page) => page.name), ['ChildARoute']);
    expect(_created['ChildBRoute'], isNull);
    expect(router.currentUrl, '/shell/a');
    final shellData = router.stack.lastOrNull?.routeData;
    expect(nested?.routeData, allOf(isNotNull, same(shellData)));
    expect(
      nested?.stack.singleOrNull?.routeData.parent,
      allOf(isNotNull, same(shellData)),
    );
  });

  // Steps: push ShellRoute showing ChildARoute, call replaceAll with
  // HomeRoute, ShellRoute showing ChildBRoute, and GuardedRoute, whose guard
  // takes its time, let it in, then pop.
  // Happened: while the guard decided, the shell already showed ChildBRoute
  // and sent /shell/b; then /guarded went in as a new history entry.
  // Should: while the guard decides, the shell keeps ChildARoute at /shell/a
  // and nothing is sent; then /guarded replaces the history entry, and the
  // shell under it shows ChildBRoute.
  testWidgets('The shell on top shows the child a replaceAll names only once '
      'a guard lets the batch in', (tester) async {
    final guard = _HeldGuard();
    final router = _buildRouter(guard);
    final sent = _recordSentUrls(tester);
    await pumpRouterApp(tester, router);
    unawaited(router.push(_shell('ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    sent.clear();

    unawaited(router.replaceAll([_home, _shell('ChildBRoute'), _guarded]));
    await tester.pumpAndSettle();
    final shownWhileDeciding = find.text('ChildARoute #1').evaluate().length;
    final nestedWhileDeciding = nested?.stack.map((page) => page.name).toList();
    final urlWhileDeciding = router.currentUrl;
    final sentWhileDeciding = List.of(sent);

    guard.decision.complete(true);
    await tester.pumpAndSettle();
    expect(shownWhileDeciding, 1);
    expect(nestedWhileDeciding, ['ChildARoute']);
    expect(urlWhileDeciding, '/shell/a');
    expect(sentWhileDeciding, isEmpty);
    expect(find.text('GuardedRoute #1'), findsOneWidget);
    expect(sent, [('/guarded', true)]);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('ChildBRoute #1'), findsOneWidget);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(nested?.stack.map((page) => page.name), ['ChildBRoute']);
    expect(router.currentUrl, '/shell/b');
  });

  // Steps: push ShellRoute showing ChildARoute, call replaceAll with
  // HomeRoute, ShellRoute showing ChildBRoute, and GuardedRoute, whose guard
  // takes its time and then rejects it.
  // Happened: the shell showed ChildBRoute while the guard decided, and
  // stayed on it after the rejection.
  // Should: the shell shows ChildARoute, with its state, throughout.
  testWidgets('A guard that takes its time and rejects a replaceAll leaves '
      'the shell on top as it was', (tester) async {
    final guard = _HeldGuard();
    final router = _buildRouter(guard);
    final nested = await _replaceAllOverShell(tester, router);
    final whileDeciding = find.text('ChildARoute #1').evaluate().length;

    guard.decision.complete(false);
    await tester.pumpAndSettle();
    expect(
      (whileDeciding, find.text('ChildARoute #1').evaluate().length),
      (1, 1),
    );
    expect(nested?.stack.map((page) => page.name), ['ChildARoute']);
    expect(_created['ChildBRoute'], isNull);
    expect(router.currentUrl, '/shell/a');
  });

  // Steps: push ShellRoute showing ChildARoute and FirstRoute, then call
  // replaceAll with HomeRoute, ShellRoute showing ChildBRoute, and
  // GuardedRoute, whose guard rejects it.
  // Happened: the shell's nested router, and ChildARoute as its parent, kept
  // the route data of the rejected ShellRoute page.
  // Should: they have the route data of the shell's page put back.
  testWidgets('A replaceAll a guard rejects gives a shell kept below the top '
      'back its own route data', (tester) async {
    final guard = _HeldGuard()..decision.complete(false);
    final router = _buildRouter(guard);
    await pumpRouterApp(tester, router);
    unawaited(router.push(_shell('ChildARoute')));
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _shell('ChildBRoute'), _guarded]));
    await tester.pumpAndSettle();
    expect(find.text('FirstRoute #1'), findsOneWidget);
    expect(router.stack.map((page) => page.name), [
      'HomeRoute',
      'ShellRoute',
      'FirstRoute',
    ]);
    final shellData = router.stack.elementAtOrNull(1)?.routeData;
    expect(nested?.routeData, allOf(isNotNull, same(shellData)));
    expect(
      nested?.stack.singleOrNull?.routeData.parent,
      allOf(isNotNull, same(shellData)),
    );
  });
}
