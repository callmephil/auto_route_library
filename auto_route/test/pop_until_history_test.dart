// Off the web only: on the web the history is the browser's.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Off the web, popUntilRoot and popUntil that close more than one page
// leave no history entry for the pages they closed. After popUntilRoot over
// the pages Home, A, B and C, the history holds Home alone, so
// canNavigateBack is false and back() opens nothing. They used to keep the
// entries of the pages under the top one (Home, A, B, then Home again), so
// back() opened B again, a page popUntilRoot had just closed.
// popUntilRouteWithName, which closes the same pages one pop after the
// other, already left Home alone.
//
// Native behavior this holds to: pages closed by a pop are gone from the back
// stack. After Flutter's Navigator.popUntil to the first route, iOS's
// popToRootViewController or Android's NavController.popBackStack to the
// start destination, back never reopens one of them. A browser that goes
// back three entries leaves them ahead, not behind. The doc comment of
// NavigationHistory.rebuildUrlAfterPop says the native history drops the
// popped page's entry.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

Future<RootStackRouter> _pumpFourPages(WidgetTester tester) async {
  final router = _router();
  await pumpRouterConfigApp(tester, router.config());
  for (final name in ['ARoute', 'BRoute', 'CRoute']) {
    unawaited(router.push(NamedRoute(name)));
    await tester.pumpAndSettle();
  }
  expect(router.navigationHistory.length, 4);
  return router;
}

List<String?> _stack(RootStackRouter router) =>
    router.stack.map((page) => page.name).toList();

void main() {
  // Control: the same pages closed one pop after the other.
  testWidgets('After popUntilRouteWithName to the first page, back() has '
      'nowhere to go', (tester) async {
    final router = await _pumpFourPages(tester);
    router.popUntilRouteWithName('HomeRoute');
    await tester.pumpAndSettle();
    expect(_stack(router), ['HomeRoute']);

    expect(router.navigationHistory.length, 1);
    expect(router.canNavigateBack, isFalse);
  });

  // Steps: push A, B and C over Home, call popUntilRoot, then back().
  testWidgets('After popUntilRoot, back() does not reopen a closed page', (
    tester,
  ) async {
    final router = await _pumpFourPages(tester);
    router.popUntilRoot();
    await tester.pumpAndSettle();
    final afterPop = _stack(router).join(', ');

    router.back();
    await tester.pumpAndSettle();
    expect(
      (afterPop, _stack(router).join(', '), router.navigationHistory.length),
      ('HomeRoute', 'HomeRoute', 1),
    );
  });

  // Steps: push A, B and C over Home, popUntil A, then back() twice.
  testWidgets('After popUntil, back() does not reopen a closed page', (
    tester,
  ) async {
    final router = await _pumpFourPages(tester);
    router.popUntil((route) => route.settings.name == 'ARoute');
    await tester.pumpAndSettle();
    expect(_stack(router), ['HomeRoute', 'ARoute']);

    router.back();
    await tester.pumpAndSettle();
    expect(_stack(router), ['HomeRoute']);
  });
}
