import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The onFailure callback of replaceAll and of navigatePath never heard that a
// guard rejected the route, so the caller couldn't tell a rejected navigation
// from one that worked. Found by the audit of auto_route/lib at dev 56b73492
// (finding C16).
// Steps: open Home. Call replaceAll([GuardedRoute], onFailure: ...) and
// navigatePath('/guarded', onFailure: ...), where the guard rejects.
// Was: onFailure was not called. replaceAll kept the callback to itself, and
// navigatePath didn't hand it on.
// Should: onFailure gets a RejectedByGuardFailure, as their docs say
// ("navigation errors are passed to it"), and as push, replace, navigate,
// pushAll, pushPath, replacePath and pushAndPopUntil do.
void main() {
  late RootStackRouter router;
  late AutoRouteGuard guard;

  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  NamedRouteDef plainRoute(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => page(name),
  );

  setUp(() {
    guard = AutoRouteGuard.simple((resolver, _) => resolver.reject());
    router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute('OpenRoute', '/open'),
        plainRoute('GuardedRoute', '/guarded', guards: [guard]),
      ],
    );
  });

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  void expectRejectionOfGuardedRoute(NavigationFailure? heard) {
    expect(
      heard,
      isA<RejectedByGuardFailure>()
          .having((failure) => failure.route.name, 'route', 'GuardedRoute')
          .having((failure) => failure.guard, 'guard', guard),
    );
  }

  testWidgets('onFailure of replaceAll hears a guard rejection', (
    tester,
  ) async {
    await pumpRouterConfigApp(tester, router.config());
    final heard = <NavigationFailure>[];

    unawaited(
      router.replaceAll([
        const NamedRoute('OpenRoute'),
        const NamedRoute('GuardedRoute'),
      ], onFailure: heard.add),
    );
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute']);
    expect(heard, hasLength(1));
    expectRejectionOfGuardedRoute(heard.firstOrNull);
  });

  testWidgets('onFailure of navigatePath hears a guard rejection', (
    tester,
  ) async {
    await pumpRouterConfigApp(tester, router.config());
    final heard = <NavigationFailure>[];

    unawaited(router.navigatePath('/guarded', onFailure: heard.add));
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute']);
    expect(heard, hasLength(1));
    expectRejectionOfGuardedRoute(heard.firstOrNull);
  });

  testWidgets('onFailure of replaceAll and navigatePath stays silent when '
      'the routes open', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    final heard = <NavigationFailure>[];

    unawaited(router.navigatePath('/open', onFailure: heard.add));
    await tester.pumpAndSettle();
    unawaited(
      router.replaceAll([const NamedRoute('HomeRoute')], onFailure: heard.add),
    );
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute']);
    expect(heard, isEmpty);
  });
}
