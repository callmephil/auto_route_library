import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A nested router whose stack is emptied while a dialog shows over its page
// can no longer pop, and the AutoLeadingButton above it hides.
// Steps: the first page of the app holds a nested router showing List under
// an AppBar with an AutoLeadingButton. A dialog opens in the nested
// navigator; then every page of the nested router is removed, as an app does
// on sign-out. The nested navigator goes, and the dialog with it.
// Before the fix the nested router still said its top route was the dialog,
// so canPop() said true and a back button showed with nothing to go back
// to: the navigator that went told its observer nothing, so the observer
// kept the dialog as its top route.
// Native behavior this holds to: Flutter's Navigator.canPop is false when
// nothing is left to pop (widgets/navigator.dart), and on iOS a navigation
// controller with no view controllers shows no back button.
void main() {
  testWidgets('A nested stack emptied under a dialog can no longer pop and '
      'hides the back button', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: AppBar(leading: const AutoLeadingButton()),
            body: const AutoRouter(),
          ),
          children: [
            NamedRouteDef(
              name: 'ListRoute',
              path: '',
              builder: (_, _) => const Center(child: Text('List')),
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    final nested = router.innerRouterOf<StackRouter>('ShellRoute')!;
    showDialog<void>(
      context: nested.navigatorKey.currentContext!,
      useRootNavigator: false,
      builder: (_) => const Center(child: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    final withDialog = (nested.hasPagelessTopRoute, router.canPop());

    nested.removeWhere((_) => true);
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsNothing);
    expect(nested.stack, isEmpty);
    expect(
      (withDialog, (nested.hasPagelessTopRoute, router.canPop())),
      ((true, true), (false, false)),
    );
    final backButtonsWhenEmpty = find.byType(BackButton).evaluate().length;

    unawaited(nested.push(const NamedRoute('ListRoute')));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(
      (backButtonsWhenEmpty, find.byType(BackButton).evaluate().length),
      (0, 0),
    );
  });
}
