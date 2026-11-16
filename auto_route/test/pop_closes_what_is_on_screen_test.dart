import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A pop closed a page the user did not see on top. Found by the review of
// cb0265d5, which brought both cases.
// On Home, A, B, a removeLast, a showDialog and a pop in one handler closed
// the dialog and A too, and ended on Home. A frame apart the pop closes the
// dialog and A stays.
// On Home, A, B, with B taken off by removeWhere or removeRoute with
// notify set to false, B stays on screen, since nothing rebuilds the
// navigator. A pop frames later made B vanish and closed A too. Before, it
// closed what was on screen, B's route, and A stayed.
// The cause: before it hands a pop to the navigator, the router takes out
// the routes of pages that left the stack and still lie over its top page
// (cb0265d5). It took every such route, with every pageless route over it.
// Now it takes only the route of a page the listeners were told has left,
// so that a rebuild is on its way, with the pageless routes that lay over
// it then.
// Native behavior this holds to: Flutter's Navigator.pop closes the route
// on top, the one the user sees, so a dialog shown last is what a pop
// closes.
void main() {
  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home, A and B, a frame apart.
  Future<RootStackRouter> open(WidgetTester tester) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('ARoute', '/a'),
          ('BRoute', '/b'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => NamedPage(name),
          ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    for (final name in ['ARoute', 'BRoute']) {
      unawaited(router.push(NamedRoute(name)));
      await tester.pumpAndSettle();
    }
    return router;
  }

  void showConfirmation(StackRouter router) {
    showDialog<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Confirm')),
    );
  }

  testWidgets('A dialog shown right after removeLast is what a pop in the '
      'same turn closes', (tester) async {
    final router = await open(tester);

    router.removeLast();
    showConfirmation(router);
    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute', 'ARoute']);
    expect(find.text('ARoute'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });

  // The dialog leaves with its page, as it does a frame apart.
  testWidgets('A dialog that was open over the page removeLast took off '
      'leaves with it, and a pop in the same turn closes the page under', (
    tester,
  ) async {
    final router = await open(tester);
    showConfirmation(router);
    await tester.pumpAndSettle();

    router
      ..removeLast()
      ..pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackNames(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });

  final silentRemovals = <String, void Function(StackRouter)>{
    'removeWhere': (router) =>
        router.removeWhere((data) => data.name == 'BRoute', notify: false),
    'removeRoute': (router) {
      final top = router.stack.lastOrNull?.routeData;
      if (top != null) router.removeRoute(top, notify: false);
    },
  };

  for (final MapEntry(key: call, value: remove) in silentRemovals.entries) {
    testWidgets('A page taken off by $call with notify: false stays on '
        'screen, and a pop frames later closes it alone', (tester) async {
      final router = await open(tester);

      remove(router);
      await tester.pumpAndSettle();
      final afterRemoval = (
        stackNames(router).join(' '),
        find.text('BRoute').evaluate().length,
      );
      router.pop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(afterRemoval, ('HomeRoute ARoute', 1));
      expect(stackNames(router), ['HomeRoute', 'ARoute']);
      expect(find.text('ARoute'), findsOneWidget);
      expect(find.text('BRoute'), findsNothing);
    });
  }
}
