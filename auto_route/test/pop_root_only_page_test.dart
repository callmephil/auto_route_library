import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Issue #2258 (closed upstream as intended): after replaceAll([B]), B is the
// root router's only page, and router.pop() leaves the stack empty.
// Documented, not changed: auto_route's pop() is Navigator.pop(), which pops
// the last route with no check (widgets/navigator.dart, NavigatorState.pop;
// pinned by flutter_canary_pop_last_page_test.dart, flutter/flutter#186187).
// Android's NavController.popBackStack() pops the start destination too and
// leaves a blank screen the app must resolve (developer.android.com/guide/
// navigation/backstack, "Handle a failed pop back"). Only the calls made for
// back stop at the last page, as they do natively: Navigator.maybePop on the
// first route bubbles (Route.popDisposition is bubble when isFirst), iOS's
// popViewController does nothing on the root view controller, and a browser's
// history.back() does nothing on its first entry (HTML standard, "traverse
// the history by a delta"). So the safe calls are canPop and maybePop.
void main() {
  RootStackRouter build() => RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'A',
        path: '/',
        builder: (_, _) => const NamedPage('A'),
      ),
      NamedRouteDef(
        name: 'B',
        path: '/b',
        builder: (_, _) => const NamedPage('B'),
      ),
    ],
  );

  testWidgets('maybePop and canPop leave the only page, as a Navigator does', (
    tester,
  ) async {
    final router = build();
    await pumpRouterApp(tester, router);
    unawaited(router.replaceAll([const NamedRoute('B')]));
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.name), ['B']);
    expect(router.canPop(), isFalse);
    expect(await router.maybePop(), isFalse);
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.name), ['B']);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('pop() on the only page empties the stack, as Navigator.pop', (
    tester,
  ) async {
    final router = build();
    await pumpRouterApp(tester, router);
    unawaited(router.replaceAll([const NamedRoute('B')]));
    await tester.pumpAndSettle();

    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.stack, isEmpty);
    expect(router.canPop(), isFalse);
  });

  testWidgets('the same call on a plain Navigator empties it too', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: key, home: const Text('B')),
    );
    expect(key.currentState!.canPop(), isFalse);
    expect(await key.currentState!.maybePop(), isFalse);
    expect(find.text('B'), findsOneWidget);

    key.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('B'), findsNothing);
  });
}
