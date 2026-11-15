import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The guards are asked again after every change of the session that lands
// while a guard runs its check, also in a round that asks again: the last
// change wins, as Flutter's Router drops the answer of an older route parse
// when newer route information arrives.
// Headless test: auto_route/test/reevaluatable_router/change_in_later_round_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('change in later round', () {
    // Steps: signed in on Account, whose guard reads the session and then
    // waits for a request. The token is refreshed, and the guard is asked
    // again and waits. The token is refreshed once more while it waits, so
    // the guards are asked again once that round ends. In that second round,
    // while the guard waits, the session ends.
    // Was: Account stayed open for the signed-out user. The third change
    // took the second round's answer, from before it.
    // Should: Account closes and Home shows.
    testWidgets('A sign-out while the guard waits in the second round of '
        'its checks closes the page', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      final requests = <Completer<void>>[];
      final guard = AutoRouteGuard.simple((resolver, _) async {
        final wasSignedIn = isSignedIn.value;
        if (requests.isNotEmpty) await requests.removeAt(0).future;
        wasSignedIn ? resolver.next() : resolver.reject();
      });
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('AccountRoute', '/account', guard),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: changes);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');
      final first = Completer<void>();
      final second = Completer<void>();
      requests.addAll([first, second]);

      changes.value++;
      await tester.pump();
      changes.value++;
      await tester.pump();
      first.complete();
      await tester.pump();
      await tester.pump();
      isSignedIn.value = false;
      changes.value++;
      await tester.pump();
      second.complete();
      await tester.pumpAndSettle();

      expectTopPage(router, 'HomeRoute');
      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('AccountRoute'), findsNothing);
      await expectBrowserUrl('/');
    });
  });
}
