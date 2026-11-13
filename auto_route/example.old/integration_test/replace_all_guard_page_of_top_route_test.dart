import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A guard of replaceAll may show a page of the route that is on top already:
// its page is a page of its own, so the page it took the place of comes back
// once when the guard rejects. Flutter's Navigator takes each page of its
// list once, and Android starts a new screen for a standard activity also
// when one of its class is on top.
// Headless test: auto_route/test/guards/replace_all_guard_page_of_top_route_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replace all guard page of top route', () {
    // Steps: open Home and push Pin. The app locks and replaces the pages
    // with the vault page, whose guard sends a locked user to the pin page.
    // That pin page is the only page. The guard rejects, as a cancel button
    // on it does.
    // Was: both pin pages had one key in a stack of [Home, Pin, Pin] and the
    // screen showed Flutter's error for it.
    // Should: Home and Pin as before the call, and back shows Home.
    testWidgets('A guard of replaceAll that shows a page of the route on top '
        'and rejects leaves the pages as they were', (tester) async {
      final isLocked = ValueNotifier(false);
      addTearDown(isLocked.dispose);
      final asking = <NavigationResolver>[];
      final failures = <NavigationFailure>[];
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(
              appBar: AppBar(leading: const AutoLeadingButton()),
              body: SafeArea(child: Text(name)),
            ),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('PinRoute', '/pin'),
          page(
            'VaultRoute',
            '/vault',
            AutoRouteGuard.simple((resolver, _) {
              if (!isLocked.value) return resolver.next();
              asking.add(resolver);
              unawaited(resolver.redirectUntil(const NamedRoute('PinRoute')));
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('PinRoute')));
      await tester.pumpAndSettle();
      isLocked.value = true;
      unawaited(
        router.replaceAll([
          const NamedRoute('VaultRoute'),
        ], onFailure: failures.add),
      );
      await tester.pumpAndSettle();
      expectTopPage(router, 'PinRoute');
      expect(find.byType(BackButton), findsNothing);

      asking.singleOrNull?.reject();
      await tester.pumpAndSettle();

      expectTopPage(router, 'PinRoute');
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'PinRoute']);
      expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
      await expectBrowserUrl('/pin');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expectTopPage(router, 'HomeRoute');
      await expectBrowserUrl('/');
    });
  });
}
