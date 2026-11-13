import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, the browser's back button leaves an entry made with
// router.pushPathState, and its forward button returns to it.
// Headless test: auto_route/test/web/path_state_browser_back_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('path state browser back', () {
    // Steps: push Second, tap 'Update State', which calls
    // router.pushPathState('x'), press the browser's back button, then its
    // forward button.
    // Was: back landed on the entry before and the app at once wrote the
    // state again as a new entry, so back never left it and forward had
    // nowhere to go.
    // Should: back goes to the entry before, with no state; forward returns
    // to the entry with 'x'.
    // Native behavior: the HTML History API; back traverses to the entry
    // before, whose state popstate carries, and the entry left stays ahead.
    // Going back between two entries of one document asks no beforeunload
    // handler, so a PopScope on Second that refuses to be left isn't asked:
    // no page closes. With one, back used to be refused and the browser sent
    // forward again.
    // Web only: only the browser has a path state and these buttons.
    for (final refusesPop in [false, true]) {
      testWidgets(
        'The browser back button leaves an entry made by pushPathState'
        '${refusesPop ? ' on a page whose PopScope refuses to be left' : ''}',
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
                builder: (context, _) => PopScope<Object?>(
                  canPop: !refusesPop,
                  child: Scaffold(
                    body: SafeArea(
                      child: TextButton(
                        onPressed: () => context.router.pushPathState('x'),
                        child: const Text('Update State'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
          await pumpRouterAppWithConfig(tester, router);
          unawaited(router.push(const NamedRoute('SecondRoute')));
          await tester.pumpAndSettle();
          await expectBrowserUrl('/second');
          final second = browserEntryIndex()!;
          // The state the router reports, and Second still on screen.
          void expectOnSecondWith(Object? state) => expect(
            (router.pathState, find.text('Update State').evaluate().length),
            (state, 1),
          );

          await expectBrowserEntryAfter(1, () async {
            await tester.tap(find.text('Update State'));
            await tester.pumpAndSettle();
          });
          expectOnSecondWith('x');

          await expectBrowserEntryAfter(-1, pressBrowserBack);
          await tester.pumpAndSettle();
          // A new entry written for the old state would show up by now.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await expectBrowserEntry(second);
          expectOnSecondWith(null);
          await expectBrowserUrl('/second');

          await expectBrowserEntryAfter(1, pressBrowserForward);
          await tester.pumpAndSettle();
          expectOnSecondWith('x');
          await expectBrowserUrl('/second');
        },
        skip: !kIsWeb,
      );
    }
  });
}
