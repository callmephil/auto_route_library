import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// An AutoLeadingButton above a nested router hides its back button once the
// page under the nested top page is removed, since nothing can pop any more.
// Headless test: auto_route/test/leading_button_nested_page_removed_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('leading button nested page removed', () {
    // Steps: the app opens on a shell page whose AppBar holds an
    // AutoLeadingButton above a nested router showing List. Tap 'Open
    // details', then 'Finish flow', which removes List from under Details.
    // Was: the back button stayed, and tapping it did nothing.
    // Should: the back button goes, as Flutter's AppBar hides it when the
    // route under the page is removed.
    testWidgets(
      'The back button goes when the page under the nested top page is '
      'removed',
      (tester) async {
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
                  builder: (context, _) => Center(
                    child: TextButton(
                      onPressed: () => unawaited(
                        context.router.push(const NamedRoute('DetailsRoute')),
                      ),
                      child: const Text('Open details'),
                    ),
                  ),
                ),
                NamedRouteDef(
                  name: 'DetailsRoute',
                  path: 'details',
                  builder: (context, _) => Center(
                    child: TextButton(
                      onPressed: () {
                        final nested = context.router;
                        final [listPage, _] = nested.stackData;
                        nested.removeRoute(listPage);
                      },
                      child: const Text('Finish flow'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        final backButtonsAtStart = find.byType(BackButton).evaluate().length;

        await tester.tap(find.text('Open details'));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);

        await tester.tap(find.text('Finish flow'));
        await tester.pumpAndSettle();
        expect(find.text('Finish flow'), findsOneWidget);
        expect(router.canPop(), isFalse);
        expect(
          (
            backButtonsAtStart,
            find.byType(BackButton).evaluate().length,
          ),
          (0, 0),
        );
      },
    );
  });
}
