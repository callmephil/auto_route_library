import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A nested router whose stack is emptied while a dialog shows over its page
// hides the AutoLeadingButton above it.
// Headless test: auto_route/test/stack_emptied_under_dialog_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('stack emptied under dialog', () {
    // Steps: the app opens on a shell page whose AppBar holds an
    // AutoLeadingButton above a nested router showing List. Tap 'Open
    // dialog', which opens a dialog in the nested navigator, then tap 'Sign
    // out' in it, which removes every page of the nested router.
    // Was: a back button showed with nothing to go back to.
    // Should: the dialog closes and no back button shows.
    testWidgets(
      'A nested stack emptied under a dialog hides the back button',
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
                      onPressed: () {
                        final nested = context.router;
                        showDialog<void>(
                          context: context,
                          useRootNavigator: false,
                          builder: (_) => Center(
                            child: TextButton(
                              onPressed: () => nested.removeWhere((_) => true),
                              child: const Text('Sign out'),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open dialog'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        final backButtonsAtStart = find.byType(BackButton).evaluate().length;

        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(find.text('Sign out'), findsNothing);
        expect(find.text('Open dialog'), findsNothing);
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
