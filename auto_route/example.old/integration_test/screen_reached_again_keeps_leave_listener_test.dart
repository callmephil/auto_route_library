import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/route_leave_router.dart';

// An AutoRouteLeaveListener in a screen that a navigation reaches again keeps
// hearing the screen leave.
// Headless test: auto_route/test/simple_router/
// screen_reached_again_keeps_leave_listener_test.dart
// Flutter's Navigator keeps the Route of a page of the same type and key, so
// a PopScope registered with that route keeps hearing its pops, and UIKit's
// popToViewController keeps the view controller it goes back down to.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('screen reached again keeps leave listener', () {
    late List<RouteLeaveKind> leaves;
    late ValueNotifier<bool> editorCanPop;
    late RootStackRouter router;

    setUp(() {
      leaves = [];
      editorCanPop = ValueNotifier(true);
      router = buildRouteLeaveRouter(
        leaves: leaves,
        editorCanPop: editorCanPop,
      );
    });
    tearDown(() => editorCanPop.dispose());

    // Steps: open /editor, whose page holds an AutoRouteLeaveListener, and
    // /preview over it, follow a link back to /editor, then press system back.
    // Happened: since the listener came in (12.4.0), it heard the preview's
    // push, then nothing: it stayed with the editor's first page, and the
    // back was reported to the page that took the screen over.
    // Should: it hears the push, then the back.
    testWidgets('A back from a screen a link went back down to is heard', (
      tester,
    ) async {
      await pumpRouterApp(tester, router);
      unawaited(router.pushPath('/editor'));
      await tester.pumpAndSettle();
      unawaited(router.pushPath('/preview'));
      await tester.pumpAndSettle();
      expect(leaves, [RouteLeaveKind.covered]);

      unawaited(router.navigatePath('/editor'));
      await tester.pumpAndSettle();
      expect(find.text('Editor'), findsOneWidget);
      await expectBrowserUrl('/editor');

      await systemBack(tester);
      expect(find.text('Home'), findsOneWidget);
      expect(leaves, [RouteLeaveKind.covered, RouteLeaveKind.popped]);
      await expectBrowserUrl('/');
    });
  });
}
