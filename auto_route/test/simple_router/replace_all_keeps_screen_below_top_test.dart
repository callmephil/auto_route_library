import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// replaceAll keeps the screen of a page below the top when the new stack has
// a page of the same route at its place, counted from the bottom or from the
// top: the navigator updates that route with the new page, and the screen
// keeps its state. The code that opened the screen keeps waiting until the
// screen closes, as native navigation keeps it: a SwiftUI NavigationStack
// keeps the state of a screen whose place in the path stays, UIKit's
// setViewControllers keeps a screen passed again with its caller waiting, and
// Flutter's Navigator keeps the route, with its pending popped future, for a
// page of the same type at the same place.

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

AutoRoute _page(String name, String path) => .new(
  page: PageInfo(name, builder: (_) => _Screen(name)),
  path: path,
);

RootStackRouter _buildRouter() => .build(
  routes: [
    _page('HomeRoute', '/'),
    _page('PickerRoute', '/picker'),
    _page('FirstRoute', '/first'),
    _page('SecondRoute', '/second'),
    _page('OtherRoute', '/other'),
    AutoRoute(
      page: PageInfo('ShellRoute', builder: (_) => const AutoRouter()),
      path: '/shell',
      children: [_page('ChildRoute', 'child')],
    ),
  ],
);

const NamedRoute<Object?> _home = NamedRoute('HomeRoute');
const NamedRoute<Object?> _picker = NamedRoute('PickerRoute');
const NamedRoute<Object?> _first = NamedRoute('FirstRoute');
const NamedRoute<Object?> _second = NamedRoute('SecondRoute');
const NamedRoute<Object?> _other = NamedRoute('OtherRoute');
const NamedRoute<Object?> _shell = NamedRoute(
  'ShellRoute',
  children: [NamedRoute('ChildRoute')],
);

// What the code that opened a screen got, or that it still waits.
class _Caller {
  new(Future<Object?> future) {
    unawaited(future.then((value) => result = 'got ${value ?? 'null'}'));
  }

  String result = 'waiting';
}

void main() {
  setUp(_created.clear);

  // Steps: push PickerRoute and keep its future, push FirstRoute, replaceAll
  // with HomeRoute, PickerRoute and SecondRoute, then go back to the picker
  // and close it with 7.
  // Happened: since 12.6.0, the navigator kept the picker's screen and its
  // state, but the push answered null at the replaceAll, and the 7 went to no
  // one.
  // Should: the push waits while the picker's screen stays, and gets 7.
  testWidgets('The caller of a screen that replaceAll keeps below the top '
      'waits for the result it closes with', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final pushed = router.push(_picker);
    final caller = _Caller(pushed);
    await tester.pumpAndSettle();
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _picker, _second]));
    await tester.pumpAndSettle();
    expect(find.text('SecondRoute #1'), findsOneWidget);
    final atReplaceAll = caller.result;

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('PickerRoute #1'), findsOneWidget);
    expect((atReplaceAll, caller.result), ('waiting', 'waiting'));

    router.pop(7);
    await tester.pumpAndSettle();
    expect(find.text('HomeRoute #1'), findsOneWidget);
    expect(caller.result, 'got 7');
  });

  // Steps: push PickerRoute with push<int>, push FirstRoute, replaceAll with
  // HomeRoute, PickerRoute and SecondRoute, then go back to the picker and
  // close it with 7.
  // Happened: the picker's screen was built anew, losing its state, as its
  // route couldn't hold the new page's type, and the push answered null.
  // Should: the picker keeps its screen and its type, and the push gets 7.
  testWidgets('A screen opened with a result type that replaceAll keeps below '
      'the top keeps its state and its caller', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final caller = _Caller(router.push<int>(_picker));
    await tester.pumpAndSettle();
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _picker, _second]));
    await tester.pumpAndSettle();
    expect(caller.result, 'waiting');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('PickerRoute #1'), findsOneWidget);

    router.pop(7);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('HomeRoute #1'), findsOneWidget);
    expect(caller.result, 'got 7');
  });

  // Steps: push FirstRoute, push PickerRoute with push<int>, push
  // SecondRoute, replaceAll with HomeRoute, OtherRoute, PickerRoute and
  // SecondRoute, then go back to the picker and close it with 7.
  // Happened: the picker's screen, at its place counted from the top, was
  // built anew, and the push answered null at the replaceAll.
  // Should: the picker keeps its screen, and the push gets 7.
  testWidgets('The caller of a screen that replaceAll keeps, counted from the '
      'top, waits for it', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_first));
    await tester.pumpAndSettle();
    final caller = _Caller(router.push<int>(_picker));
    await tester.pumpAndSettle();
    unawaited(router.push(_second));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _other, _picker, _second]));
    await tester.pumpAndSettle();
    expect(find.text('SecondRoute #1'), findsOneWidget);
    expect(caller.result, 'waiting');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('PickerRoute #1'), findsOneWidget);

    router.pop(7);
    await tester.pumpAndSettle();
    expect(find.text('OtherRoute #1'), findsOneWidget);
    expect(caller.result, 'got 7');
  });

  // Steps: push PickerRoute with push<int>, push FirstRoute, then replaceAll
  // with HomeRoute and PickerRoute, and close the picker with 7.
  // Happened: the picker's screen was built anew, and the push answered null
  // at the replaceAll.
  // Should: the picker keeps its screen, and the push gets 7.
  testWidgets('The caller of a screen that replaceAll brings back to the top '
      'waits for it', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final caller = _Caller(router.push<int>(_picker));
    await tester.pumpAndSettle();
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _picker]));
    await tester.pumpAndSettle();
    expect(find.text('PickerRoute #1'), findsOneWidget);
    expect(caller.result, 'waiting');

    router.pop(7);
    await tester.pumpAndSettle();
    expect(caller.result, 'got 7');
  });

  // Steps: push ShellRoute showing ChildRoute and keep its future, push
  // FirstRoute, replaceAll with HomeRoute, ShellRoute and SecondRoute, then
  // go back to the shell.
  // Happened: since 12.6.0, the push answered null at the replaceAll, though
  // the shell kept its screen.
  // Should: the shell keeps its nested router, which shows ChildRoute and
  // its url, and the push waits.
  testWidgets('A shell that replaceAll keeps below the top keeps its nested '
      'router and its caller', (tester) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final pushed = router.push(_shell);
    final caller = _Caller(pushed);
    await tester.pumpAndSettle();
    final nested = router.innerRouterOf<StackRouter>('ShellRoute');
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _shell, _second]));
    await tester.pumpAndSettle();
    final atReplaceAll = caller.result;

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('ChildRoute #1'), findsOneWidget);
    expect(router.innerRouterOf<StackRouter>('ShellRoute'), same(nested));
    expect(router.currentUrl, '/shell/child');
    expect((atReplaceAll, caller.result), ('waiting', 'waiting'));
  });

  // Steps: push PickerRoute with push<int>, push FirstRoute, then replaceAll
  // with HomeRoute, OtherRoute and PickerRoute.
  // Should: the picker's place changed, so the navigator builds its screen
  // anew, and the push answers null as the old screen leaves, as for every
  // screen that leaves the stack since 12.6.0.
  testWidgets('The caller of a screen that replaceAll builds anew gets null', (
    tester,
  ) async {
    final router = _buildRouter();
    await pumpRouterApp(tester, router);
    final caller = _Caller(router.push<int>(_picker));
    await tester.pumpAndSettle();
    unawaited(router.push(_first));
    await tester.pumpAndSettle();

    unawaited(router.replaceAll([_home, _other, _picker]));
    await tester.pumpAndSettle();
    expect(find.text('PickerRoute #2'), findsOneWidget);
    expect(caller.result, 'got null');
  });
}
