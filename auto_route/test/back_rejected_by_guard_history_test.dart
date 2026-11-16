// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Off the web, when a guard rejects the page that the router's back method
// goes to, the history stays as it was: the page on screen keeps its entry,
// and the next back step tries the same page again. The back step used to
// drop that entry before the guard answered, so the history was one entry
// short, and once the guard let the user through, the back step skipped the
// guarded page.
//
// Native behavior this holds to: a refused navigation changes nothing. In
// Flutter's Navigator, a pop that a PopScope refuses leaves every route in
// place; on Android, a back press that an OnBackPressedCallback consumes
// leaves the back stack as it was.
//
// Steps: open Tabs on its guarded tab, then show the Feed tab, which leaves
// three entries. Close the guard and take a back step with the router's back
// method, then open the guard and take another.
//
// The setup used to push Guarded and then navigate to Home underneath it,
// which kept Guarded's entry although Guarded had left the stack. The history
// now drops the entry of a page the app removed, so back() never reopens a
// closed page and a guard is asked only on the way back into a tab.
void main() {
  testWidgets('Off the web, back() to a page whose guard rejects keeps the '
      'history', (tester) async {
    final isOpen = ValueNotifier(true);
    addTearDown(isOpen.dispose);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/tabs',
          builder: (_, _) => const AutoTabsRouter(
            routes: [
              NamedRoute<Object?>('GuardedTab'),
              NamedRoute<Object?>('FeedTab'),
            ],
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
    final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!
      ..setActiveIndex(1);
    await tester.pumpAndSettle();
    final history = router.navigationHistory;
    // The history's length, the url, and the name of the tab shown.
    (int, String, String) shown() =>
        (history.length, history.urlState.url, tabs.current.name);
    // Before, after the rejected back step, and after the one let through.
    final readings = [shown()];
    for (final isLetThrough in [false, true]) {
      isOpen.value = isLetThrough;
      router.back();
      await tester.pumpAndSettle();
      readings.add(shown());
    }
    expect(readings, [
      (3, '/tabs/feed', 'FeedTab'),
      (3, '/tabs/feed', 'FeedTab'),
      (2, '/tabs/guarded', 'GuardedTab'),
    ]);
  });
}
