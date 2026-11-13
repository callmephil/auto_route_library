import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A navigation called right after a push, in the same handler with no await
// between them, acted on the stack without the pushed page, so the wrong page
// left: from Home, push(A) then replace(B) dropped Home and kept A.
// Steps, from [Home], each pair called one after the other with no await:
// push(A) then replace(B), replacePath('/b'), replaceAll([B]),
// navigate(Home), popAndPush(B) or removeLast(); and from [Home, A],
// replace(B) then replace(C).
// Native behavior this holds to: Flutter's Navigator changes its history as
// each call is made, so Navigator.push followed by pushReplacement replaces
// the route just pushed, and by pushAndRemoveUntil removes it. On the web
// history.pushState followed by replaceState replaces the new entry. On iOS
// pushViewController followed by setViewControllers ends on the list given,
// and on Android two FragmentManager transactions run in the order they
// were committed.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
  const c = NamedRoute('CRoute');
  const home = NamedRoute('HomeRoute');

  NamedRouteDef page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => NamedPage(name));

  Future<RootStackRouter> open(WidgetTester tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('ARoute', '/a'),
        page('BRoute', '/b'),
        page('CRoute', '/c'),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    return router;
  }

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  final afterPush = {
    'replace': (
      run: (StackRouter router) => unawaited(router.replace(b)),
      expected: ['HomeRoute', 'BRoute'],
    ),
    'replacePath': (
      run: (StackRouter router) => unawaited(router.replacePath('/b')),
      expected: ['HomeRoute', 'BRoute'],
    ),
    'replaceAll': (
      run: (StackRouter router) => unawaited(router.replaceAll([b])),
      expected: ['BRoute'],
    ),
    'navigate to the page below': (
      run: (StackRouter router) => unawaited(router.navigate(home)),
      expected: ['HomeRoute'],
    ),
    'popAndPush': (
      run: (StackRouter router) => unawaited(router.popAndPush(b)),
      expected: ['HomeRoute', 'BRoute'],
    ),
    'removeLast': (
      run: (StackRouter router) => router.removeLast(),
      expected: ['HomeRoute'],
    ),
  };

  for (final MapEntry(key: name, value: call) in afterPush.entries) {
    testWidgets('$name right after a push acts on the pushed page', (
      tester,
    ) async {
      final router = await open(tester);

      unawaited(router.push(a));
      call.run(router);
      await tester.pumpAndSettle();

      expect(stackNames(router), call.expected);
      expect(find.text(router.topRoute.name), findsOneWidget);
    });
  }

  testWidgets('replace right after a replace leaves one page in place of the '
      'top', (tester) async {
    final router = await open(tester);
    unawaited(router.push(a));
    await tester.pumpAndSettle();

    unawaited(router.replace(b));
    unawaited(router.replace(c));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'CRoute']);
    expect(find.text('CRoute'), findsOneWidget);
  });

  // Should: the page is on the stack as push returns, as a route is in the
  // Navigator's history as Navigator.push returns, and the page that takes
  // its place takes its history entry too, so one step back shows Home.
  testWidgets('a pushed page is on the stack as the call returns', (
    tester,
  ) async {
    final router = await open(tester);

    unawaited(router.push(a));

    expect(stackNames(router), ['HomeRoute', 'ARoute']);
    expect(router.topRoute.name, 'ARoute');
    expect(router.currentUrl, '/a');

    unawaited(router.replace(b));
    await tester.pumpAndSettle();

    expect(router.currentUrl, '/b');
    // The headless runner in Chrome writes no browser entries to count.
    if (!kIsWeb) expect(router.navigationHistory.length, 2);
  });

  // A push called right after a navigation that is still on its way in, such
  // as replaceAll, navigate or pushPath, lands after it, in the order of the
  // calls, as Flutter's Navigator applies its calls in order.
  final beforePush = {
    'replaceAll': (
      run: (StackRouter router) => unawaited(router.replaceAll([b])),
      expected: ['BRoute', 'ARoute'],
    ),
    'navigate': (
      run: (StackRouter router) => unawaited(router.navigate(b)),
      expected: ['HomeRoute', 'BRoute', 'ARoute'],
    ),
    'pushPath': (
      run: (StackRouter router) => unawaited(router.pushPath('/b')),
      expected: ['HomeRoute', 'BRoute', 'ARoute'],
    ),
    'replacePath': (
      run: (StackRouter router) => unawaited(router.replacePath('/b')),
      expected: ['BRoute', 'ARoute'],
    ),
  };

  for (final MapEntry(key: name, value: call) in beforePush.entries) {
    testWidgets('a push right after $name lands on top of its page', (
      tester,
    ) async {
      final router = await open(tester);

      call.run(router);
      unawaited(router.push(a));
      await tester.pumpAndSettle();

      expect(stackNames(router), call.expected);
      expect(find.text('ARoute'), findsOneWidget);
    });
  }
}
