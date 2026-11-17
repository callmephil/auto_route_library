import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Canary for Flutter bug https://github.com/flutter/flutter/issues/150978:
// text laid out before a nested Navigator leaves the semantics tree, so a
// screen reader skips it. On iOS and Android every text on screen is in the
// accessibility tree, wherever it sits beside another view.
// Setup, without auto_route: the reporter's page, a Scaffold whose Row holds
// Text('Left 1'), a Padding, Text('Left 2'), an Expanded nested Navigator
// showing Text('Center') and an Expanded Text('Right'), with semantics on.
// A Navigator given pages, as auto_route's, drops the same texts.
// Steps: pump the page and look for each text in the semantics tree.
// Today, on Flutter 3.50.0 (and 3.47.9): 'Left 1' and 'Left 2' are missing,
// while 'Center' and 'Right' are there. The nested Navigator's route blocks the
// nodes painted before it, and a parent that forms no semantics node of its
// own takes that block from its children, so it also blocks nodes that are
// not the route's siblings: `_RenderObjectSemantics.isBlockingPreviousSibling`
// in flutter lib/src/rendering/object.dart:5747. Flutter's thread confirms
// the bug and names a container node around the Navigator as the
// workaround; the control test below shows it works.
// auto_route wraps each nested router's Navigator in such a container, in
// `AutoRouteNavigatorState.build`
// (lib/src/router/widgets/auto_route_navigator.dart). If this test fails
// after a Flutter upgrade, Flutter fixed the bug: drop the container (and
// its explicitChildNodes, which only keep the container's child nodes
// steady for flutter/flutter#194873), check that
// test/nested_router_semantics_test.dart still passes, and drop this canary.
void main() {
  Widget page(Widget navigator) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Row(
          mainAxisSize: .min,
          mainAxisAlignment: .spaceEvenly,
          children: [
            const Text('Left 1'),
            const Padding(padding: .all(8)),
            const Text('Left 2'),
            Expanded(child: navigator),
            const Expanded(child: Text('Right')),
          ],
        ),
      ),
    ),
  );

  // The reporter's nested Navigator, built with onGenerateRoute.
  final nestedNavigator = Navigator(
    onGenerateRoute: (settings) => PageRouteBuilder<void>(
      settings: settings,
      pageBuilder: (_, _, _) => const Text('Center'),
    ),
  );

  testWidgets(
    'text before a nested Navigator is missing from the semantics tree, '
    'until Flutter fixes flutter/flutter#150978',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(page(nestedNavigator));

      expect(find.bySemanticsLabel('Left 1'), findsNothing);
      expect(find.bySemanticsLabel('Left 2'), findsNothing);
      expect(find.bySemanticsLabel('Center'), findsOneWidget);
      expect(find.bySemanticsLabel('Right'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('the control: a container node around the Navigator keeps '
      'every text in the semantics tree', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      page(Semantics(container: true, child: nestedNavigator)),
    );

    for (final label in ['Left 1', 'Left 2', 'Center', 'Right']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    semantics.dispose();
  });
}
