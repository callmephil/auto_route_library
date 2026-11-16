import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard that asks the user in a dialog asked twice when the session changed
// while its dialog was open. Found by the review of a05b2755, which asks a
// guard again before its page goes in when the router's reevaluateListenable
// changes while the guard checks.
// Setup: Home, and Draft behind a guard that shows a "Leave draft?" dialog
// and lets Draft in on "Yes", whatever the session says. The session is the
// router's reevaluateListenable.
// Steps: push(DraftRoute()). While the dialog is open, the session's token is
// refreshed, or the user signs out, and the listenable notifies. The user
// taps "Yes".
// Was: the dialog closed and opened again; Draft opened only after a second
// "Yes". a05b2755 took the guard's answer for one from before the change, as
// it does for a guard that awaits a request, and asked it again. Only a page
// the guard put on a stack told that it waits on the user.
// Should: one dialog, one "Yes", and Draft opens. The guard answers from the
// user, as a guard behind its own login page does. An alert on iOS
// (UIAlertController) or Android (AlertDialog) stays up through what the app
// does meanwhile, and its answer is acted on once.
void main() {
  late ValueNotifier<bool> isSignedIn;
  late ValueNotifier<int> session;
  late int guardCalls;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    session = ValueNotifier(0);
    addTearDown(session.dispose);
    guardCalls = 0;
  });

  // Asks the user in a dialog, whatever the session says.
  final confirmGuard = AutoRouteGuard.simple((resolver, router) async {
    guardCalls++;
    final isConfirmed = await showDialog<bool>(
      context: router.root.navigatorKey.currentContext!,
      builder: (dialog) => AlertDialog(
        title: const Text('Leave draft?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    (isConfirmed ?? false) ? resolver.next() : resolver.reject();
  });

  NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  Future<void> expectAskedOnce(
    WidgetTester tester,
    void Function() change,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('DraftRoute', '/draft', confirmGuard),
      ],
    );
    await pumpRouterConfigApp(
      tester,
      router.config(reevaluateListenable: session),
    );
    unawaited(router.push(const NamedRoute('DraftRoute')));
    await tester.pumpAndSettle();
    final dialogsAtFirst = find.text('Leave draft?').evaluate().length;

    change();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(dialogsAtFirst, 1);
    expect(find.text('Leave draft?'), findsNothing);
    expect(router.stack.map((page) => page.routeData.name), [
      'HomeRoute',
      'DraftRoute',
    ]);
    expect(find.text('DraftRoute'), findsOneWidget);
    expect(guardCalls, 1);
  }

  testWidgets('A guard that asks in a dialog asks once when the token is '
      'refreshed while the dialog is open', (tester) async {
    await expectAskedOnce(tester, () => session.value++);
  });

  testWidgets('A guard that asks in a dialog asks once when the user signs '
      'out while the dialog is open', (tester) async {
    await expectAskedOnce(tester, () {
      isSignedIn.value = false;
      session.value++;
    });
  });
}
