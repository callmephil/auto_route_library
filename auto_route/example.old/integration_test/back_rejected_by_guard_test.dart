import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, a router.back() whose target a guard rejects keeps the
// history, so once the guard lets the user through, back() reaches the
// guarded page.
// Headless test: auto_route/test/back_rejected_by_guard_history_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back rejected by guard', () {
    // Steps: open Tabs on its guarded tab, then tap 'Feed', which leaves
    // three history entries. Close the guard and tap 'Back', whose handler is
    // the router's back method. Open the guard and tap 'Back' again.
    // Was: the rejected back dropped Feed's entry, so the second tap skipped
    // the guarded tab and stayed on Feed.
    // Should: the rejected back changes nothing; the second tap shows the
    // guarded tab.
    // The steps used to push Guarded and navigate to Home underneath it,
    // which kept Guarded's entry; the history now drops the entry of a page
    // the app removed, so the guard is asked on the way back into a tab.
    // Native behavior: a refused navigation changes nothing, as a pop a
    // PopScope refuses leaves every route of Flutter's Navigator in place.
    // Off the web only: on the web, back() is the browser's own back step.
    testWidgets(
      'back() to a page whose guard rejects keeps the history',
      (tester) async {
        final isOpen = ValueNotifier(true);
        addTearDown(isOpen.dispose);
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
            ),
            NamedRouteDef(
              name: 'TabsRoute',
              path: '/tabs',
              builder: (context, _) => Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: context.router.back,
                        child: const Text('Back'),
                      ),
                      const Expanded(
                        child: AutoTabsRouter(
                          routes: [
                            NamedRoute<Object?>('GuardedTab'),
                            NamedRoute<Object?>('FeedTab'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              children: [
                NamedRouteDef(
                  name: 'GuardedTab',
                  path: 'guarded',
                  guards: [
                    AutoRouteGuard.simple(
                      (resolver, _) =>
                          isOpen.value ? resolver.next() : resolver.reject(),
                    ),
                  ],
                  builder: (_, _) => const Text('GuardedTab'),
                ),
                NamedRouteDef(
                  name: 'FeedTab',
                  path: 'feed',
                  builder: (_, _) => const Text('FeedTab'),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('TabsRoute')));
        await tester.pumpAndSettle();
        router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
        await tester.pumpAndSettle();

        isOpen.value = false;
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        final onFeed = find.text('FeedTab').hitTestable().evaluate().length;

        isOpen.value = true;
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        final onGuarded = find
            .text('GuardedTab')
            .hitTestable()
            .evaluate()
            .length;
        expect((onFeed, onGuarded), (1, 1));
      },
      skip: kIsWeb,
    );
  });
}
