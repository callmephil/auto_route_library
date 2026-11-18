// Off the web only: on the web, the browser keeps its own history.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// Issue 16 of the fork: back() to an entry whose page is still open asked
// the guard of that page again. The system back button closes the same page
// and asks no guard.
// Steps: push MessageRoute, whose guard counts its calls, then push
// SettingsRoute, then call back(). The guard count must stay 1, as after the
// system back button.
// Native behavior this holds to: Flutter's Navigator.pop removes the top
// route and gives the route under it only didPopNext (Flutter 3.50.0,
// widgets/navigator.dart). Android's back pops the top destination of the
// back stack, and iOS's popViewController(animated:) shows the view
// controller under it. None checks the page that shows again.
class _CountGuard extends AutoRouteGuard {
  int calls = 0;
  Completer<void>? hold;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    calls++;
    final wait = hold;
    if (wait == null) {
      resolver.next();
    } else {
      unawaited(wait.future.then((_) => resolver.next()));
    }
  }
}

RootStackRouter _router(_CountGuard guard) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const NamedPage('Home'),
    ),
    NamedRouteDef(
      name: 'MessageRoute',
      path: '/message',
      guards: [guard],
      builder: (_, _) => const NamedPage('Message'),
    ),
    NamedRouteDef(
      name: 'SettingsRoute',
      path: '/settings',
      builder: (_, _) => const NamedPage('Settings'),
    ),
  ],
);

String _names(StackRouter router) =>
    router.stack.map((page) => page.routeData.name).join(' > ');

void main() {
  for (final isSystem in [false, true]) {
    testWidgets(
      '${isSystem ? 'the system back button' : 'back()'} to an open page '
      'asks no guard',
      (tester) async {
        final guard = _CountGuard();
        final router = _router(guard);
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.push(const NamedRoute('MessageRoute')));
        await tester.pumpAndSettle();
        expect(guard.calls, 1);
        unawaited(router.push(const NamedRoute('SettingsRoute')));
        await tester.pumpAndSettle();
        if (isSystem) {
          await router.maybePop();
        } else {
          router.back();
        }
        await tester.pumpAndSettle();
        expect((_names(router), guard.calls), ('HomeRoute > MessageRoute', 1));
      },
    );
  }

  testWidgets('a slow guard of an open page does not delay back()', (
    tester,
  ) async {
    final guard = _CountGuard();
    final router = _router(guard);
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('MessageRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('SettingsRoute')));
    await tester.pumpAndSettle();
    guard.hold = Completer<void>();
    router.back();
    await tester.pumpAndSettle();
    expect((_names(router), guard.calls), ('HomeRoute > MessageRoute', 1));
    guard.hold!.complete();
    await tester.pumpAndSettle();
  });
}
