import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
import '../router_test_utils.dart';

// In a router built by AutoRouter.declarative, the first page's
// AutoLeadingButton kept a back button after the page above it was popped,
// though nothing could pop any more; the button did nothing. Found by the
// audit of auto_route/lib at dev 56b73492 (finding W6).
// Cause: _DeclarativeAutoRouterState.build read the router's state hash for
// its RouterScope before the navigator applied the app's new list, and didn't
// listen to its router, so the scope's hash was one update late. The widgets
// that watch the router, such as AutoLeadingButton, kept what they showed.
// Steps: a host page builds AutoRouter.declarative with [ListRoute, if
// (isSelected) DetailsRoute]; ListRoute's AppBar has an AutoLeadingButton.
// Select, then press back; with onPopRoute clearing the selection, as an app
// should, and without.
// Should: no back button, since the router can no longer pop, as on the
// first page of an AutoRouter. Flutter's AppBar shows a back button
// only while its route can pop: material/app_bar.dart reads the route's
// impliesAppBarDismissal.
class _Host extends StatelessWidget {
  const new({required this.selected, required this.doesHandlePop});

  final ValueNotifier<bool> selected;
  final bool doesHandlePop;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: selected,
      builder: (context, isSelected, _) => AutoRouter.declarative(
        routes: (_) => [
          const NamedRoute('ListRoute'),
          if (isSelected) const NamedRoute('DetailsRoute'),
        ],
        onPopRoute: doesHandlePop ? (_, _) => selected.value = false : null,
      ),
    );
  }
}

void main() {
  for (final doesHandlePop in [true, false]) {
    testWidgets(
      'doesHandlePop: $doesHandlePop; the list page has no back button after '
      'the details page is popped',
      (tester) async {
        final selected = ValueNotifier(false);
        addTearDown(selected.dispose);
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HostRoute',
              path: '/',
              builder: (_, _) =>
                  _Host(selected: selected, doesHandlePop: doesHandlePop),
              children: [
                NamedRouteDef(
                  name: 'ListRoute',
                  path: '',
                  builder: (_, _) => Scaffold(
                    appBar: AppBar(leading: const AutoLeadingButton()),
                    body: const Text('List'),
                  ),
                ),
                NamedRouteDef(
                  name: 'DetailsRoute',
                  path: 'details',
                  builder: (_, _) => const Scaffold(body: Text('Details')),
                ),
              ],
            ),
          ],
        );
        await pumpRouterApp(tester, router);
        final backButtonsAtStart = find.byType(BackButton).evaluate().length;

        selected.value = true;
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsOneWidget);

        await systemBack(tester);
        expect(find.text('List'), findsOneWidget);
        expect(find.text('Details'), findsNothing);
        final inner = router.innerRouterOf<StackRouter>('HostRoute')!;
        expect(inner.stack.map((page) => page.name), ['ListRoute']);
        expect(router.canPop(), isFalse);
        expect(
          (backButtonsAtStart, find.byType(BackButton).evaluate().length),
          (0, 0),
        );
      },
    );
  }
}
