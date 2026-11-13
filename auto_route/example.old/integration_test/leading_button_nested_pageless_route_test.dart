import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// An AutoLeadingButton above a nested router shows the back button for a
// page the nested router opens with pushWidget, and tapping it closes that
// page.
// Headless test: auto_route/test/leading_button_nested_pageless_route_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('leading button nested pageless route', () {
    // Steps: the app opens on a shell page whose AppBar holds an
    // AutoLeadingButton above a nested router showing List. Tap 'Open
    // pushed', which opens a page with pushWidget in the nested router, then
    // tap the back button.
    // Was: no back button showed, though the router could pop.
    // Should: the back button shows, and tapping it goes back to List.
    testWidgets(
      'A page opened with pushWidget in the nested router shows the back '
      'button',
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
                        context.router.pushWidget<void>(
                          const Center(child: Text('Pushed')),
                        ),
                      ),
                      child: const Text('Open pushed'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        final backButtonsAtStart = find.byType(BackButton).evaluate().length;

        await tester.tap(find.text('Open pushed'));
        await tester.pumpAndSettle();
        expect(find.text('Pushed'), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Pushed'), findsNothing);
        expect(find.text('Open pushed'), findsOneWidget);
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
