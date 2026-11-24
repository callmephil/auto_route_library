import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, pushAndPopUntil into a tabs page that shows another tab
// leaves no entry of the old tab ahead (callmephil/auto_route_library#47).
// Headless tests: auto_route/test/push_and_pop_until_into_tabs_page_test.dart
// and auto_route/test/web/push_and_pop_until_into_tabs_page_web_test.dart.
//
// Native behavior this holds to: Flutter's Navigator.pushAndRemoveUntil,
// where the removed routes do not come back, and the HTML standard's
// history.pushState, which drops the entries ahead. Web only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pushAndPopUntil into a tabs page that shows another tab', () {
    // Steps: on Home, push Tabs on tab One and select tab Two. Call
    // pushAndPopUntil of Tabs on tab One until Home. Press the browser's
    // forward button, then its back button.
    // Was: forward showed tab Two again, and back then showed tab One.
    // Should: forward finds no entry, and back shows Home at '/'.
    testWidgets(
      'Forward finds no entry, and back shows Home',
      (tester) async {
        final router = _router();
        await pumpRouterAppWithConfig(tester, router);
        final home = browserEntryIndex()!;
        unawaited(router.push(const NamedRoute<Object?>('TabsRoute')));
        await tester.pumpAndSettle();
        router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(1);
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 2);
        await expectBrowserUrl('/tabs/two');

        unawaited(
          router.pushAndPopUntil(
            const NamedRoute<Object?>(
              'TabsRoute',
              children: [NamedRoute('OneRoute')],
            ),
            predicate: (route) => route.settings.name == 'HomeRoute',
          ),
        );
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);
        await expectBrowserUrl('/tabs/one');
        expect(router.topRoute.name, 'OneRoute');

        // Back lands on Home only when the forward press found no entry
        // ahead: after a forward to tab Two, it lands on tab One again.
        pressBrowserForward();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        pressBrowserBack();
        await expectBrowserEntry(home);
        await tester.pumpAndSettle();
        await expectBrowserUrl('/');
        expect(router.topRoute.name, 'HomeRoute');
      },
      skip: !kIsWeb,
    );
  });
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router() => .build(
  routes: [
    _page('HomeRoute', '/'),
    NamedRouteDef(
      name: 'TabsRoute',
      path: '/tabs',
      builder: (_, _) => AutoTabsRouter(
        routes: const [NamedRoute('OneRoute'), NamedRoute('TwoRoute')],
        builder: (_, child) => child,
      ),
      children: [_page('OneRoute', 'one'), _page('TwoRoute', 'two')],
    ),
  ],
);
