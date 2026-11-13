import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// redirectUntil(replace: true) to a page that did not open took the page the
// user was on off the stack, while it stayed on screen. Found by the audit of
// auto_route/lib at dev 56b73492 (finding C10).
// Steps: open Home, push Details. Push Account, whose guard calls
// resolver.redirectUntil(LoginRoute, replace: true); LoginRoute's own guard
// rejects it, or no route matches the target.
// Was: the stack was [Home] while Details stayed on screen at its url; the
// next change of the stack took Details off the screen, and back skipped it.
// The redirect removed the top page, without telling the navigator, before
// the target's guards ran, and nothing put it back.
// Should: a replace that does not happen leaves the page it would replace.
// Flutter's Navigator.pushReplacement takes the old route off in the same
// step that pushes the new one, and on the web a canceled replace navigation
// leaves the current entry; replace and replacePath hold to this already.
void main() {
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

  // Account's guard redirects to [target] with replace; Login's guard lets
  // it in when [isLoginOpen].
  RootStackRouter buildRouter({
    required PageRouteInfo target,
    bool isLoginOpen = false,
    OnNavigationFailure? onFailure,
  }) => .build(
    routes: [
      plainRoute('HomeRoute', '/'),
      plainRoute('DetailsRoute', '/details'),
      plainRoute(
        'LoginRoute',
        '/login',
        guards: [
          AutoRouteGuard.simple(
            (resolver, _) => isLoginOpen ? resolver.next() : resolver.reject(),
          ),
        ],
      ),
      plainRoute(
        'AccountRoute',
        '/account',
        guards: [
          AutoRouteGuard.simple(
            (resolver, _) => unawaited(
              resolver.redirectUntil(
                target,
                replace: true,
                onFailure: onFailure,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  Future<void> openDetailsThenAccount(
    WidgetTester tester,
    RootStackRouter router,
  ) async {
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
  }

  testWidgets('redirectUntil(replace: true) to a rejected page keeps the page '
      'it would replace', (tester) async {
    final router = buildRouter(target: const NamedRoute('LoginRoute'));
    await openDetailsThenAccount(tester, router);

    final stackAfterRedirect = stackNames(router);
    final shownAfterRedirect = find.text('DetailsRoute').evaluate().length;
    expect(router.currentUrl, '/details');

    // Back from the next page shows Details again.
    unawaited(router.push(const NamedRoute('HomeRoute')));
    await tester.pumpAndSettle();
    unawaited(router.maybePop());
    await tester.pumpAndSettle();

    expect(stackAfterRedirect, ['HomeRoute', 'DetailsRoute']);
    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
    expect(
      (shownAfterRedirect, find.text('DetailsRoute').evaluate().length),
      (1, 1),
    );
  });

  testWidgets('redirectUntil(replace: true) to a page no route matches keeps '
      'the page it would replace', (tester) async {
    NavigationFailure? heard;
    final router = buildRouter(
      target: const NamedRoute('MissingRoute'),
      onFailure: (failure) => heard = failure,
    );
    await openDetailsThenAccount(tester, router);

    expect(heard, isA<RouteNotFoundFailure>());
    expect(find.text('DetailsRoute'), findsOneWidget);
    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
  });

  // The replace still happens when the target opens.
  testWidgets('redirectUntil(replace: true) to a page that opens replaces the '
      'page on top', (tester) async {
    final router = buildRouter(
      target: const NamedRoute('LoginRoute'),
      isLoginOpen: true,
    );
    await openDetailsThenAccount(tester, router);

    expect(stackNames(router), ['HomeRoute', 'LoginRoute']);
    expect(find.text('LoginRoute'), findsOneWidget);
  });
}
