import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A router's PagelessRoutesObserver says no dialog is on top once its
// navigator has gone. Steps: the first page of the app holds a nested router
// showing List; a dialog opens in the nested navigator; then every page of
// the nested router is removed, as an app does on sign-out, so the nested
// navigator goes and the dialog with it. Before, the observer, read directly,
// still said a pageless route was on top: a navigator that goes clears its
// observers' navigator and sends them no callback, so the flag kept its last
// value until a new navigator reported.
// Native behavior this holds to: Flutter's NavigatorObserver.navigator is
// null once its navigator is deactivated (widgets/navigator.dart,
// NavigatorState.deactivate), and a navigator that is gone holds no route,
// so nothing is on top of it; on iOS a navigation controller that is gone
// presents nothing.
void main() {
  testWidgets('The observer of a nested router emptied under a dialog says '
      'no dialog is on top', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'ShellRoute',
          path: '/',
          builder: (_, _) => const AutoRouter(),
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
    final observer = nested.pagelessRoutesObserver;
    showDialog<void>(
      context: nested.navigatorKey.currentContext!,
      useRootNavigator: false,
      builder: (_) => const Center(child: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    final withDialog = observer.hasPagelessTopRoute;

    nested.removeWhere((_) => true);
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsNothing);
    expect((withDialog, observer.hasPagelessTopRoute), (true, false));
  });

  testWidgets('A dialog over a page of a navigator still shown is on top', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('Home'),
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    final observer = router.pagelessRoutesObserver;
    final before = observer.hasPagelessTopRoute;
    showDialog<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const Center(child: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    expect((before, observer.hasPagelessTopRoute), (false, true));
  });
}
