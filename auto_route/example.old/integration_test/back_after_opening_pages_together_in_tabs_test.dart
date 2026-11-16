import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, router.back() after pages opened together in a tab shows
// them before an earlier change of tabs.
// Headless test: auto_route/test/back_after_opening_pages_together_in_tabs_test.dart.
//
// Native behavior this holds to: within the tab's stack, Navigator.pop
// takes the top-most route only (navigator.dart 5617 and 5652, Flutter
// 3.47.9). Off the web only: on the web, back() is the browser's own back
// step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pages opened together in a tab, off the web', () {
    // Steps: on Home, push Tabs; change to tab Two and back to One; call
    // replaceAll([X1, Y1]) in One. Call back().
    // Was: back() showed tab Two, with X1 still under Y1.
    // Should: back() shows X1.
    testWidgets(
      'back() after replaceAll in a tab shows the page under, not the other '
      'tab',
      (tester) async {
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
              builder: (_, _) => const Scaffold(
                body: AutoTabsRouter(
                  routes: [
                    NamedRoute<Object?>('OneTab'),
                    NamedRoute<Object?>('TwoTab'),
                  ],
                ),
              ),
              children: [
                NamedRouteDef(
                  name: 'OneTab',
                  path: 'one',
                  builder: (_, _) => const AutoRouter(),
                  children: [
                    for (final (name, path) in [
                      ('H1Route', ''),
                      ('X1Route', 'x'),
                      ('Y1Route', 'y'),
                    ])
                      NamedRouteDef(
                        name: name,
                        path: path,
                        builder: (_, _) => Text(name),
                      ),
                  ],
                ),
                NamedRouteDef(
                  name: 'TwoTab',
                  path: 'two',
                  builder: (_, _) => const Text('TwoTab'),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('TabsRoute')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
        for (final index in [1, 0]) {
          tabs.setActiveIndex(index);
          await tester.pumpAndSettle();
        }
        unawaited(
          tabs.innerRouterOf<StackRouter>('OneTab')!.replaceAll(const [
            NamedRoute('X1Route'),
            NamedRoute('Y1Route'),
          ]),
        );
        await tester.pumpAndSettle();

        router.back();
        await tester.pumpAndSettle();

        expect((tabs.activeIndex, router.currentUrl), (0, '/tabs/one/x'));
        expect(find.text('X1Route').hitTestable(), findsOneWidget);
      },
      skip: kIsWeb,
    );
  });
}
