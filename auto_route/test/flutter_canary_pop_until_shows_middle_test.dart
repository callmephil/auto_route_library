import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Canary for Flutter bug https://github.com/flutter/flutter/issues/59990:
// Navigator.popUntil shows each page in between while it pops. On iOS,
// UINavigationController.popToViewController(_:animated:) and
// popToRootViewController(animated:) slide only the top page away, straight
// onto the page they stop at; Android's NavController.popBackStack(id,
// inclusive) likewise plays the top destination's exit over the one it pops
// to.
// Setup, without auto_route: the reporter's app, a Scaffold whose body is a
// nested Navigator built with onGenerateRoute, its first page 'Page 0'.
// Steps: push 'Page 1' and 'Page 2' with MaterialPageRoute, then call
// popUntil((route) => route.isFirst) and record every page on screen in
// each frame of the pop.
// Today, on Flutter 3.50.0 (and 3.47.9): 'Page 1' shows during the pop, as
// popUntil calls pop on each route in turn and each plays its own exit
// animation: `NavigatorState.popUntil` in
// flutter lib/src/widgets/navigator.dart:5681. Flutter's thread keeps it
// open as a bug.
// auto_route's popUntil and popUntilRoot don't call Navigator.popUntil while
// the router knows the top route: `_didPopUntilShowingNoneBetween` in
// lib/src/router/controller/routing_controller.dart removes the routes in
// between first, then pops the top one. If this test fails after a Flutter
// upgrade, Flutter fixed the bug: let popUntil call Navigator.popUntil again,
// check that test/nested_router/pop_until_hides_middle_test.dart still
// passes, and drop this canary.
void main() {
  // Pushes 'Page 1' and 'Page 2' over 'Page 0', calls popUntil with
  // [predicate], and returns every page on screen during the pop.
  Future<Set<String>> pagesShownWhilePopping(
    WidgetTester tester,
    RoutePredicate predicate,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    Widget page(String name) => Center(child: Text(name));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            key: navigatorKey,
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => page('Page 0'),
            ),
          ),
        ),
      ),
    );
    for (final name in ['Page 1', 'Page 2']) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name),
          builder: (_) => page(name),
        ),
      );
      await tester.pumpAndSettle();
    }

    navigatorKey.currentState!.popUntil(predicate);
    final shown = <String>{};
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final name in ['Page 0', 'Page 1', 'Page 2']) {
        if (find.text(name).evaluate().isNotEmpty) shown.add(name);
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsNothing);
    return shown;
  }

  testWidgets('popUntil shows the page in between while it pops, until '
      'Flutter fixes flutter/flutter#59990', (tester) async {
    final shown = await pagesShownWhilePopping(
      tester,
      (route) => route.isFirst,
    );

    expect(shown, {'Page 0', 'Page 1', 'Page 2'});
    expect(find.text('Page 0'), findsOneWidget);
  });

  testWidgets('the control: popUntil that pops one page shows only it and '
      'the page under it', (tester) async {
    final shown = await pagesShownWhilePopping(
      tester,
      (route) => route.settings.name == 'Page 1',
    );

    expect(shown, {'Page 1', 'Page 2'});
  });
}
