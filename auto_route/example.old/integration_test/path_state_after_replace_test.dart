import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, router.pushPathState adds a browser entry also right after a
// replace, and pushPathState(null) adds one without a state.
// Headless test: auto_route/test/web/path_state_after_replace_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('path state after replace', () {
    // Steps: push Second, replace it with Third, tap 'State y', which pushes
    // the path state 'y'. Then tap 'No state', which pushes null, and press
    // the browser's back button twice.
    // Was: 'State y' wrote over the entry of Third, and 'No state' added no
    // entry and kept 'y'.
    // Should: each tap adds an entry; back goes to 'y', then to Third with
    // no state.
    // Native behavior: history.pushState always adds an entry, also right
    // after a replaceState, and takes null as a state like any other.
    // Web only: only the browser has a path state.
    testWidgets(
      'pushPathState adds an entry after a replace, and for null',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
            ),
            NamedRouteDef(
              name: 'SecondRoute',
              path: '/second',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('SecondRoute'))),
            ),
            NamedRouteDef(
              name: 'ThirdRoute',
              path: '/third',
              builder: (context, _) => Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () => context.router.pushPathState('y'),
                        child: const Text('State y'),
                      ),
                      TextButton(
                        onPressed: () => context.router.pushPathState(null),
                        child: const Text('No state'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        await pumpRouterAppWithConfig(tester, router);
        unawaited(router.push(const NamedRoute('SecondRoute')));
        await tester.pumpAndSettle();
        unawaited(router.replace(const NamedRoute('ThirdRoute')));
        await tester.pumpAndSettle();
        await expectBrowserUrl('/third');
        final third = browserEntryIndex()!;
        // The state the router reports, and Third still on screen.
        void expectOnThirdWith(Object? state) => expect(
          (router.pathState, find.text('State y').evaluate().length),
          (state, 1),
        );

        for (final (button, state) in [('State y', 'y'), ('No state', null)]) {
          await expectBrowserEntryAfter(1, () async {
            await tester.tap(find.text(button));
            await tester.pumpAndSettle();
          });
          expectOnThirdWith(state);
        }

        for (final (entry, state) in [(third + 1, 'y'), (third, null)]) {
          pressBrowserBack();
          await expectBrowserEntry(entry);
          await tester.pumpAndSettle();
          expectOnThirdWith(state);
        }
        await expectBrowserUrl('/third');
      },
      skip: !kIsWeb,
    );
  });
}
