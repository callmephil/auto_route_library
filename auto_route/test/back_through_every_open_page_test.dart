// Off the web only: on the web, the browser keeps its own history.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Issue callmephil/auto_route_library#17: the app's own history kept at most
// 21 entries. After 30 pushes, router.back() took 20 steps and then did
// nothing, with 11 pages still open, and canNavigateBack was false, while
// the system back button could still close pages.
// Steps: push PageRoute 30 times (n from 1 to 30), then call router.back()
// until router.canNavigateBack is false.
// Native behavior this holds to: Flutter's Navigator keeps every route until
// it is popped; Android's back stack and iOS's UINavigationController have no
// fixed length, and back closes each page down to the first one.
const _pushes = 30;

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const NamedPage('Home'),
    ),
    NamedRouteDef(
      name: 'PageRoute',
      path: '/p/:n',
      builder: (_, data) => NamedPage('Page ${data.params.getString('n')}'),
    ),
  ],
);

void main() {
  testWidgets('back() returns through all 31 open pages, one per call', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    for (var n = 1; n <= _pushes; n++) {
      unawaited(
        router.push(PageRouteInfo('PageRoute', rawPathParams: {'n': n})),
      );
      await tester.pumpAndSettle();
    }
    expect(router.stack.length, _pushes + 1);
    var steps = 0;
    while (router.canNavigateBack && steps < 100) {
      final before = router.stack.length;
      router.back();
      await tester.pumpAndSettle();
      expect(router.stack.length, before - 1);
      steps++;
    }
    expect(steps, _pushes);
    expect(router.stack.length, 1);
    expect(router.canNavigateBack, isFalse);
  });
}
