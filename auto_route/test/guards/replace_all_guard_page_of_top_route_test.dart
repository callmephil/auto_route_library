import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard of replaceAll may show a page of the route that is on top already.
// Found while correcting the fixes of round 4 of the library audit.
// Setup: Home and Pin are open to everyone. Vault sits behind a guard that
// sends a locked user to the pin page with redirectUntil.
// Steps: open Home and push Pin, as a user who opens the pin page themself.
// The app locks and calls replaceAll([VaultRoute()]): the guard's pin page
// is the only page. The guard rejects, as a cancel button does.
// Was: the stack was [Home, Pin, Pin] with one key for both pin pages, which
// fails an assertion of Flutter's Navigator. The guard's pin page took over
// the screen and the match id of the pin page that replaceAll was setting
// aside. The redirect looks for its page by the id it gave it, found none to
// remove, and the pin page set aside came back beside it under the same id.
// Should: [Home, Pin], as before the call, with the pin page shown once. A
// page set aside may come back, so the guard's page is a page of its own.
// Flutter's Navigator takes each page of its list once, and Android starts a
// new screen for a standard activity also when one of its class is on top.
void main() {
  // Opens Home and pushes Pin, locks, and calls replaceAll([VaultRoute()]),
  // which the guard holds behind its own pin page. The guard's resolver goes
  // to [asking], and what replaceAll reports to [failures].
  Future<RootStackRouter> lockOnPinPage(
    WidgetTester tester, {
    required List<NavigationResolver> asking,
    required List<NavigationFailure> failures,
  }) async {
    final isLocked = ValueNotifier(false);
    addTearDown(isLocked.dispose);
    NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) =>
        .new(
          name: name,
          path: path,
          guards: [?guard],
          builder: (_, _) => Scaffold(body: Text(name)),
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
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('PinRoute')));
    await tester.pumpAndSettle();
    isLocked.value = true;
    unawaited(
      router.replaceAll([
        const NamedRoute('VaultRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.routeData.name), ['PinRoute']);
    return router;
  }

  testWidgets('A guard of replaceAll that shows a page of the route on top '
      'and rejects leaves the pages as they were', (tester) async {
    final asking = <NavigationResolver>[];
    final failures = <NavigationFailure>[];
    final router = await lockOnPinPage(
      tester,
      asking: asking,
      failures: failures,
    );

    asking.singleOrNull?.reject();
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.routeData.name), [
      'HomeRoute',
      'PinRoute',
    ]);
    expect(
      router.stack.map((page) => page.routeData.matchId).toSet().length,
      2,
    );
    expect(find.text('PinRoute'), findsOneWidget);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('HomeRoute'), findsOneWidget);
  });

  testWidgets('A guard of replaceAll that shows a page of the route on top '
      'and lets the new page in leaves that page alone', (tester) async {
    final asking = <NavigationResolver>[];
    final failures = <NavigationFailure>[];
    final router = await lockOnPinPage(
      tester,
      asking: asking,
      failures: failures,
    );

    asking.singleOrNull?.next();
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.routeData.name), ['VaultRoute']);
    expect(find.text('VaultRoute'), findsOneWidget);
    expect(failures, isEmpty);
  });
}
