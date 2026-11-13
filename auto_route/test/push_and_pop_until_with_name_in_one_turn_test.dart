import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// pushAndPopUntil with Flutter's ModalRoute.withName removed the named page,
// and every page under it, when that page had been pushed in the same turn:
// from Home, push(A) and pushAndPopUntil(D, predicate: withName('ARoute'))
// with no await between them ended on D alone, with no page to go back to.
// The cause: the navigator has no route yet for a page pushed in the same
// turn, so the predicate is asked about a stand-in route. The stand-in was a
// bare Route, and withName accepts a ModalRoute only, so it turned A down,
// and then Home, whose name is another.
// Steps, from Home, called one after the other with no await: push(A), or
// pushAll([A, B]), then pushAndPopUntil(D) with a predicate that stops at A.
// Native behavior this holds to: Flutter's Navigator adds a route to its
// history as push is called, and pushAndRemoveUntil asks its predicate about
// the routes of that history. So Navigator.push(A) and pushAndRemoveUntil(D,
// ModalRoute.withName('A')) in one turn hand the predicate A's own route and
// end on D over A.
void main() {
  const a = NamedRoute('ARoute');
  const b = NamedRoute('BRoute');
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

  final predicates = <String, RoutePredicate>{
    'ModalRoute.withName': ModalRoute.withName('ARoute'),
    'a predicate that asks for a page route': (route) =>
        route is PageRoute && route.settings.name == 'ARoute',
  };

  for (final MapEntry(key: asked, value: predicate) in predicates.entries) {
    testWidgets('pushAndPopUntil with $asked keeps the page pushed in the '
        'same turn', (tester) async {
      final router = await open(tester);

      unawaited(router.push(a));
      unawaited(router.pushAndPopUntil(d, predicate: predicate));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(router), ['HomeRoute', 'ARoute', 'DRoute']);
      expect(find.text('DRoute'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('ARoute'), findsOneWidget);
    });
  }

  testWidgets('pushAndPopUntil with ModalRoute.withName removes the pages of '
      'the same turn above the named one', (tester) async {
    final router = await open(tester);

    unawaited(router.pushAll([a, b]));
    unawaited(
      router.pushAndPopUntil(d, predicate: ModalRoute.withName('ARoute')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute', 'ARoute', 'DRoute']);
    expect(router.currentUrl, '/d');
  });

  // The same calls a frame apart, which worked before, for comparison.
  testWidgets('pushAndPopUntil with ModalRoute.withName keeps a page already '
      'on screen', (tester) async {
    final router = await open(tester);

    unawaited(router.push(a));
    await tester.pumpAndSettle();
    unawaited(
      router.pushAndPopUntil(d, predicate: ModalRoute.withName('ARoute')),
    );
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'ARoute', 'DRoute']);
  });
}
