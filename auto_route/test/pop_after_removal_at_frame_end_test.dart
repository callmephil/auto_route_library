import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A pop closed the route of a page that had left, and the page under it
// stayed open. On Home, A, B, C the app registers a callback for the end of
// the frame that calls removeLast, then calls removeLast. The frame builds
// the navigator without C, and at its end the callback takes B off. A pop
// before the next frame ended on Home, A, where it ends on Home. Found by
// the review of 2feb5f7d; the same before it.
// The cause: the router notes each page the app takes off, to take its
// route out of the navigator before a pop. It dropped every note at the end
// of the frame that followed the first removal, B's note too, which the
// app's callback had made a moment before, though the navigator still
// showed B. Now only the notes of pages the navigator no longer shows are
// dropped then.
// Native behavior this holds to: Flutter's Navigator no longer counts a
// route as present from the call that removed it, whenever in a frame that
// call is made, so its next pop takes the route below.
void main() {
  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home and the pages named over it, a frame apart.
  Future<RootStackRouter> open(WidgetTester tester, List<String> names) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('ARoute', '/a'),
          ('BRoute', '/b'),
          ('CRoute', '/c'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => NamedPage(name),
          ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    for (final name in names) {
      unawaited(router.push(NamedRoute(name)));
      await tester.pumpAndSettle();
    }
    return router;
  }

  testWidgets('A pop before the next frame closes the page under one taken '
      'off at the end of the frame that rebuilt the navigator', (tester) async {
    final router = await open(tester, ['ARoute', 'BRoute', 'CRoute']);

    // Registered first, so it runs before any callback of the router.
    SchedulerBinding.instance.addPostFrameCallback((_) => router.removeLast());
    router.removeLast();
    await tester.pump();
    final afterFrame = stackNames(router);
    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(afterFrame, ['HomeRoute', 'ARoute']);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(find.text('ARoute'), findsNothing);
  });

  // With no removal before the frame nothing was dropped, and this held.
  testWidgets('A pop before the next frame closes the page under one taken '
      'off at the end of a frame', (tester) async {
    final router = await open(tester, ['ARoute', 'BRoute']);

    SchedulerBinding.instance
      ..addPostFrameCallback((_) => router.removeLast())
      ..scheduleFrame();
    await tester.pump();
    final afterFrame = stackNames(router);
    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(afterFrame, ['HomeRoute', 'ARoute']);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
  });
}
