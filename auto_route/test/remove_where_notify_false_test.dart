import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// removeWhere(notify: false) told the router's listeners anyway and rebuilt
// the url, once for every page it removed; with notify true it told them
// once per page and once more at the end.
// Steps: open Home, push A, push B. Call
// removeWhere((route) => route.name != 'HomeRoute', notify: false), as a
// caller does that pushes another page right after and wants one update.
// Then the same with notify left on.
// Native behavior this holds to: Flutter's Navigator takes a change to
// several of its pages as one update, and the parameter means what
// removeRoute documents for its own: listeners are told only if it is true.
void main() {
  NamedRouteDef page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => NamedPage(name));

  Future<RootStackRouter> openHomeAB(WidgetTester tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('ARoute', '/a'),
        page('BRoute', '/b'),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('ARoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('BRoute')));
    await tester.pumpAndSettle();
    return router;
  }

  bool isNotHome(RouteData<Object?> route) => route.name != 'HomeRoute';

  testWidgets('removeWhere with notify false tells no listener', (
    tester,
  ) async {
    final router = await openHomeAB(tester);
    var notifications = 0;
    void count() => notifications++;
    router.addListener(count);
    addTearDown(() => router.removeListener(count));

    final didRemove = router.removeWhere(isNotHome, notify: false);

    expect(didRemove, isTrue);
    expect(router.stack.map((page) => page.routeData.name), ['HomeRoute']);
    expect(notifications, 0);
    expect(router.currentUrl, '/b');

    router.notifyAll(forceUrlRebuild: true);
    await tester.pumpAndSettle();

    expect(router.currentUrl, '/');
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  testWidgets('removeWhere tells its listeners once for all the pages it '
      'removes', (tester) async {
    final router = await openHomeAB(tester);
    var notifications = 0;
    void count() => notifications++;
    router.addListener(count);
    addTearDown(() => router.removeListener(count));

    final didRemove = router.removeWhere(isNotHome);
    await tester.pumpAndSettle();

    expect(didRemove, isTrue);
    expect(notifications, 1);
    expect(router.currentUrl, '/');
    expect(find.text('HomeRoute'), findsOneWidget);
  });
}
