import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// router.waitForTransitions() waits for a page that a navigation updated in
// place, as for any other page.
// Headless test: auto_route/test/transitions/wait_for_transitions_after_page_update_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('wait for transitions after page update', () {
    const duration = Duration(milliseconds: 600);

    RootStackRouter buildRouter() => .build(
      routes: [
        AutoRoute(
          path: '/',
          page: PageInfo('HomeRoute', builder: (_) => const Text('HomeRoute')),
          initial: true,
        ),
        CustomRoute(
          path: '/book/:id',
          page: PageInfo(
            'BookRoute',
            builder: (data) => Scaffold(
              body: Text('Book ${data.params.getString('id')}'),
            ),
          ),
          transitionsBuilder: TransitionsBuilders.fadeIn,
          duration: duration,
          reverseDuration: duration,
        ),
      ],
    );

    // Pumps frames until [done] completes; fails after five times the
    // transition's duration.
    Future<void> pumpUntilDone(WidgetTester tester, Future<void> done) async {
      final isDone = ValueNotifier(false);
      addTearDown(isDone.dispose);
      unawaited(done.then((_) => isDone.value = true));
      final stopwatch = Stopwatch()..start();
      while (!isDone.value) {
        if (stopwatch.elapsed > duration * 5) {
          fail('waitForTransitions() did not complete');
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // Steps: push book 1, then navigate to book 2, which updates the screen
    // in place. Pop it and await router.waitForTransitions().
    // Was: the wait completed while book 2 was still fading out.
    // Should: it completes once book 2 has left, as a route's animation
    // belongs to the Route and stays when its page is updated.
    testWidgets('a pop of a page navigate updated in place is waited for', (
      tester,
    ) async {
      final router = buildRouter();
      await pumpRouterApp(tester, router);
      unawaited(router.push(const NamedRoute('BookRoute', params: {'id': 1})));
      await tester.pumpAndSettle();
      unawaited(
        router.navigate(const NamedRoute('BookRoute', params: {'id': 2})),
      );
      await tester.pumpAndSettle();
      final book = ModalRoute.of(tester.element(find.text('Book 2')))!;

      router.pop();
      await pumpUntilDone(tester, router.waitForTransitions());
      expect(book.animation!.status, AnimationStatus.dismissed);
      expectTopPage(router, 'HomeRoute');
    });
  });
}
