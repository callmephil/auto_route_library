import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// An AutoLeadingButton above a nested router shows the back button when the
// nested router opens a pageless route, such as a page opened with
// pushWidget, pushNativeRoute or Navigator.push, and tapping it closes that
// route.
// Steps: the first page of the app holds a nested router under an AppBar
// with an AutoLeadingButton, the setup the class doc describes. The nested
// page opens a page with pushWidget.
// Before the fix no back button showed, though the router could pop: the
// button rebuilt on the pageless routes of its own router only, not of the
// routers nested below it. The same page opened with push() shows the button
// (control).
// Native behavior this holds to: the class doc says the button "will always
// [pop] the top-most route in the whole hierarchy"; Flutter's AppBar shows
// a back button whenever the route that holds it can pop
// (material/app_bar.dart, ModalRoute.impliesAppBarDismissal).
void main() {
  late RootStackRouter router;

  setUp(() {
    router = RootStackRouter.build(
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
  });

  testWidgets('Control: a page pushed in the nested router shows the back '
      'button', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    final backButtonsAtStart = find.byType(BackButton).evaluate().length;

    final nested = router.innerRouterOf<StackRouter>('ShellRoute')!;
    unawaited(nested.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
    expect(
      (backButtonsAtStart, find.byType(BackButton).evaluate().length),
      (0, 0),
    );
  });

  testWidgets('A page opened with pushWidget in the nested router shows the '
      'back button', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    final backButtonsAtStart = find.byType(BackButton).evaluate().length;

    final nested = router.innerRouterOf<StackRouter>('ShellRoute')!;
    unawaited(nested.pushWidget<void>(const Center(child: Text('Pushed'))));
    await tester.pumpAndSettle();
    expect(find.text('Pushed'), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
    expect(
      (backButtonsAtStart, find.byType(BackButton).evaluate().length),
      (0, 0),
    );
  });
}
