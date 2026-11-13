import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// An AutoLeadingButton above a nested router hides its back button once the
// page under the nested top page is removed, since nothing can pop any more.
// Steps: the first page of the app holds a nested router under an AppBar
// with an AutoLeadingButton, the setup the class doc describes. The nested
// router shows [ListRoute, DetailsRoute]; remove ListRoute with removeRoute,
// as an app does once a flow has no way back.
// Before the fix the button kept a back button that did nothing: it rebuilt
// only when the state hash of its own router changed, which holds the top
// page of each nested router but not how many pages a nested router has.
// Native behavior this holds to: Flutter's AppBar follows
// ModalRoute.impliesAppBarDismissal, which a route updates when the route
// under it is removed (material/app_bar.dart; widgets/routes.dart,
// ModalRoute.didChangePrevious); UINavigationController hides the back
// button of a view controller that becomes the root after setViewControllers.
void main() {
  testWidgets('The back button goes when the page under the nested top page '
      'is removed', (tester) async {
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
            NamedRouteDef(
              name: 'DetailsRoute',
              path: 'details',
              builder: (_, _) => const Center(child: Text('Details')),
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    final backButtonsAtStart = find.byType(BackButton).evaluate().length;
    final nested = router.innerRouterOf<StackRouter>('ShellRoute')!;
    unawaited(nested.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);

    final [listPage, _] = nested.stackData;
    nested.removeRoute(listPage);
    await tester.pumpAndSettle();
    expect(nested.stack.map((page) => page.name), ['DetailsRoute']);
    expect(find.text('Details'), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(
      (backButtonsAtStart, find.byType(BackButton).evaluate().length),
      (0, 0),
    );
  });
}
