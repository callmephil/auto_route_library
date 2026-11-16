import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, back() into a tab whose guard waits, then lets the tab in,
// steps back once: the next back() goes on to the tab before, never to the
// tab just left.
// Headless test:
// auto_route/test/nested_tabs_router/back_into_waiting_tab_guard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back into waiting tab guard', () {
    // Steps: open Tabs and show Feed, Mail and Settings, in that order. Tap
    // 'Back', whose handler is the router's back method: Mail's guard waits
    // until the test lets it in. Then tap 'Back' again.
    // Was: the second tap showed Settings again, the tab just left.
    // Should: it shows Feed, as when the guard answers at once.
    // Native behavior: a step back is one step, as History.back() moves one
    // entry back and Android's back finishes the screen on top for good.
    // Off the web only: on the web, back() is the browser's own back step.
    testWidgets(
      'back() into a tab whose guard waits steps back once',
      (tester) async {
        // The guard's wait, which the test ends.
        final deciding = ValueNotifier<Completer<void>?>(null);
        addTearDown(deciding.dispose);
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
                            NamedRoute<Object?>('FeedTab'),
                            NamedRoute<Object?>('MailTab'),
                            NamedRoute<Object?>('SettingsTab'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              children: [
                NamedRouteDef(
                  name: 'FeedTab',
                  path: 'feed',
                  builder: (_, _) => const Text('FeedTab'),
                ),
                NamedRouteDef(
                  name: 'MailTab',
                  path: 'mail',
                  guards: [
                    AutoRouteGuard.simple((resolver, _) async {
                      await deciding.value?.future;
                      resolver.next();
                    }),
                  ],
                  builder: (_, _) => const Text('MailTab'),
                ),
                NamedRouteDef(
                  name: 'SettingsTab',
                  path: 'settings',
                  builder: (_, _) => const Text('SettingsTab'),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('TabsRoute')));
        await tester.pumpAndSettle();
        final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;
        for (final index in [1, 2]) {
          tabs.setActiveIndex(index);
          await tester.pumpAndSettle();
        }
        int settingsShown() =>
            find.text('SettingsTab').hitTestable().evaluate().length;
        final onSettings = settingsShown();

        final decided = deciding.value = Completer<void>();
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect((onSettings, settingsShown()), (1, 1));
        decided.complete();
        await tester.pumpAndSettle();
        expect(find.text('MailTab').hitTestable(), findsOneWidget);

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('FeedTab').hitTestable(), findsOneWidget);
        expect(router.currentUrl, '/tabs/feed');
      },
      skip: kIsWeb,
    );
  });
}
