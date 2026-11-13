import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The first page of AutoRouter.declarative shows no back button once the page
// above it is popped.
// Headless test: auto_route/test/nested_router/declarative_leading_button_after_pop_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('declarative leading button after pop', () {
    // Steps: a host page builds AutoRouter.declarative with [ListRoute, if
    // (isSelected) DetailsRoute]; ListRoute's AppBar has an
    // AutoLeadingButton. Tap 'Select', then go back; onPopRoute clears the
    // selection.
    // Was: the list page showed a back button that did nothing.
    // Should: no back button, as Flutter's AppBar shows one only while its
    // route can pop.
    testWidgets('the list page has no back button after the details close', (
      tester,
    ) async {
      final isSelected = ValueNotifier(false);
      addTearDown(isSelected.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HostRoute',
            path: '/',
            builder: (_, _) => ValueListenableBuilder(
              valueListenable: isSelected,
              builder: (_, selected, _) => AutoRouter.declarative(
                routes: (_) => [
                  const NamedRoute('ListRoute'),
                  if (selected) const NamedRoute('DetailsRoute'),
                ],
                onPopRoute: (_, _) => isSelected.value = false,
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'ListRoute',
                path: '',
                builder: (_, _) => Scaffold(
                  appBar: AppBar(leading: const AutoLeadingButton()),
                  body: TextButton(
                    onPressed: () => isSelected.value = true,
                    child: const Text('Select'),
                  ),
                ),
              ),
              NamedRouteDef(
                name: 'DetailsRoute',
                path: 'details',
                builder: (_, _) => Scaffold(
                  appBar: AppBar(leading: const AutoLeadingButton()),
                  body: const Text('Details'),
                ),
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      final backButtonsAtStart = find.byType(BackButton).evaluate().length;

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      await systemBack(tester);
      expect(find.text('Details'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
      expect(
        (
          backButtonsAtStart,
          find.byType(BackButton).evaluate().length,
        ),
        (0, 0),
      );
    });
  });
}
