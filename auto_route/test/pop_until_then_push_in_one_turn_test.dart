import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A push called right after popUntilRoot, in the same handler with no await
// between them, was lost when pages had been pushed earlier in that handler:
// from Home, push(A), popUntilRoot(), push(D) ended on Home alone. With two
// pages pushed before, Flutter's Navigator also failed its assertion "An
// OverlayEntry should be removed only once" and the screen stayed empty.
// The cause: the navigator has no route yet for a page pushed in the same
// turn, so popUntilRoot waited for the frame that builds it. By then the
// page pushed after it was on the stack too, and was closed with the others.
// Steps, from Home, called one after the other with no await: pages pushed
// with push or pushAll, then popUntilRoot, popUntil or popUntilRouteWithName,
// then push(D).
// Native behavior this holds to: Flutter's Navigator changes its history as
// each call is made, so Navigator.push, popUntil and push again in one turn
// end on the route pushed last, over the route popUntil stopped at. On iOS
// pushViewController, popToRootViewController and pushViewController in a
// row end on the root with the last controller over it.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const c = NamedRoute('CRoute');
  const d = NamedRoute('DRoute');

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  Future<RootStackRouter> open(WidgetTester tester) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('ARoute', '/a'),
          ('BRoute', '/b'),
          ('CRoute', '/c'),
          ('DRoute', '/d'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => NamedPage(name),
          ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    return router;
  }

  final beforePopUntilRoot = {
    'one page pushed': (StackRouter router) => unawaited(router.push(a)),
    'two pages pushed': (StackRouter router) {
      unawaited(router.push(a));
      unawaited(router.push(b));
    },
    'three pages of pushAll': (StackRouter router) =>
        unawaited(router.pushAll([a, b, c])),
  };

  for (final MapEntry(key: pushed, value: pushPages)
      in beforePopUntilRoot.entries) {
    testWidgets('After $pushed, popUntilRoot and a push in one turn end on '
        'the pushed page over the first', (tester) async {
      final router = await open(tester);

      pushPages(router);
      router.popUntilRoot();
      unawaited(router.push(d));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(router), ['HomeRoute', 'DRoute']);
      expect(find.text('DRoute'), findsOneWidget);
      expect(router.currentUrl, '/d');
    });
  }

  // Should: the pages pushed in the same turn are off the stack as
  // popUntilRoot returns, and the code that pushed them gets null, as from
  // any page that is closed without a result.
  testWidgets('Pages pushed in the same turn leave as popUntilRoot returns', (
    tester,
  ) async {
    final router = await open(tester);
    Object? resultOfA = 'not answered';

    unawaited(router.push<Object>(a).then((result) => resultOfA = result));
    unawaited(router.push(b));
    router.popUntilRoot();

    expect(stackNames(router), ['HomeRoute']);

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(resultOfA, isNull);
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  // Steps: A is open and on screen. Then B is pushed, popUntilRoot is called
  // and D is pushed, in one turn.
  // Should: both leave, B which the navigator has not built and A which it
  // shows, and D is on top of Home.
  testWidgets('popUntilRoot closes a page on screen and one pushed in the '
      'same turn, and keeps a page pushed after it', (tester) async {
    final router = await open(tester);
    unawaited(router.push(a));
    await tester.pumpAndSettle();

    unawaited(router.push(b));
    router.popUntilRoot();
    unawaited(router.push(d));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute', 'DRoute']);
    expect(find.text('DRoute'), findsOneWidget);
  });

  final popsUntilA = {
    'popUntilRouteWithName': (StackRouter router) =>
        router.popUntilRouteWithName('ARoute'),
    'popUntil': (StackRouter router) =>
        router.popUntil((route) => route.settings.name == 'ARoute'),
    'popUntil with ModalRoute.withName': (StackRouter router) =>
        router.popUntil(ModalRoute.withName('ARoute')),
  };

  for (final MapEntry(key: name, value: popUntilA) in popsUntilA.entries) {
    testWidgets('$name stops at a page pushed in the same turn, and a push '
        'right after it lands above that page', (tester) async {
      final router = await open(tester);

      unawaited(router.pushAll([a, b, c]));
      popUntilA(router);
      unawaited(router.push(d));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(router), ['HomeRoute', 'ARoute', 'DRoute']);
      expect(find.text('DRoute'), findsOneWidget);
    });
  }

  // Right after replaceAll the navigator still shows the pages that left, so
  // popUntilRoot waits for it, as before, and keeps the one new page.
  testWidgets('popUntilRoot right after replaceAll keeps the new first page', (
    tester,
  ) async {
    final router = await open(tester);

    unawaited(router.replaceAll([a]));
    router.popUntilRoot();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['ARoute']);
    expect(find.text('ARoute'), findsOneWidget);
  });
}
