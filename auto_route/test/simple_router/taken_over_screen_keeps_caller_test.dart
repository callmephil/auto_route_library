import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import '../tap_count_page.dart';

// A push over a page that keeps no history, and a replace, answered the code
// that opened the page with null although the new page, one of the same
// route, took over the page's screen: the screen stayed, with its State, and
// the result it closed with reached no one. Found while fixing the audit's
// guard findings.
// Steps: open Home, push<int> the picker for item 1 and count a tap on it.
// Then push the picker for item 2 over it (the picker keeps no history), or
// replace it with the picker for item 2. Close the picker with the result 7.
// Was: the first push finished with null as the second page went on, while
// the picker stayed on screen with its count. The page taken off answered its
// caller at once, before the new page took over its screen and its wait.
// navigate to the picker for item 2 already kept the caller waiting.
// Should: a screen that stays keeps the code that opened it waiting, and
// gives it the result it closes with. Flutter's Navigator keeps the route and
// its future for a page of the same type and key, and iOS, macOS, Android and
// the web keep a screen reached again with its caller waiting. A page whose
// screen does leave, as under a page of another route, still answers null.
void main() {
  NamedRouteDef pickerRoute({required bool keepHistory}) => .new(
    name: 'PickerRoute',
    path: '/picker/:id',
    keepHistory: keepHistory,
    builder: (_, data) => TapCountPage('Picker ${data.params.rawMap['id']}'),
  );

  RootStackRouter buildRouter({required bool keepHistory}) => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
      ),
      pickerRoute(keepHistory: keepHistory),
      NamedRouteDef(
        name: 'OtherRoute',
        path: '/other',
        builder: (_, _) => const Scaffold(body: Text('OtherRoute')),
      ),
    ],
  );

  const pickerForSecond = NamedRoute('PickerRoute', params: {'id': 2});
  const other = NamedRoute('OtherRoute');

  // Opens the picker for item 1 with push<int> and counts a tap on it.
  // Returns what that push got so far.
  Future<String Function()> openPicker(
    WidgetTester tester,
    RootStackRouter router,
  ) async {
    await pumpRouterApp(tester, router);
    var result = 'waiting';
    unawaited(
      router
          .push<int>(const NamedRoute('PickerRoute', params: {'id': 1}))
          .then((value) => result = 'got ${value ?? 'null'}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Picker 1 0'));
    await tester.pumpAndSettle();
    return () => result;
  }

  final calls = <String, Future<void> Function(StackRouter, PageRouteInfo)>{
    'push over a page that keeps no history': (router, route) =>
        router.push(route),
    'replace': (router, route) => router.replace(route),
  };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    final keepsHistory = name == 'replace';

    testWidgets('$name with a page of the same route keeps the caller of the '
        'screen waiting', (tester) async {
      final router = buildRouter(keepHistory: keepsHistory);
      final result = await openPicker(tester, router);

      unawaited(call(router, pickerForSecond));
      await tester.pumpAndSettle();

      // The screen stayed, with its count, and shows the new item.
      expect(find.text('Picker 2 1'), findsOneWidget);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'PickerRoute',
      ]);
      final resultWhileOpen = result();

      unawaited(router.maybePop(7));
      await tester.pumpAndSettle();

      expect((resultWhileOpen, result()), ('waiting', 'got 7'));
      expect(find.text('HomeRoute'), findsOneWidget);
    });

    testWidgets('$name with a page of another route answers the caller of '
        'the page that left', (tester) async {
      final router = buildRouter(keepHistory: keepsHistory);
      final result = await openPicker(tester, router);

      unawaited(call(router, other));
      await tester.pumpAndSettle();

      expect(find.text('OtherRoute'), findsOneWidget);
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'OtherRoute',
      ]);
      expect(result(), 'got null');
    });
  }
}
