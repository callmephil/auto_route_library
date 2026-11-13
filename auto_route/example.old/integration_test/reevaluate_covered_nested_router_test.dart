import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A sign-out closes the guarded page of a nested router also while another
// page covers the page that holds the router, so going back doesn't show it:
// every guard is asked again, as Flutter's Router parses its whole
// configuration again when its route information changes.
// Headless test: auto_route/test/reevaluatable_router/reevaluate_covered_nested_router_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('reevaluate covered nested router', () {
    // Steps: a shell page holds a nested router with List and, behind a
    // guard, Account. Push Account in the shell, then Details at the root,
    // over the shell. The session signs out. Go back from Details.
    // Was: Account showed after the back, as its guard was not asked.
    // Should: List shows.
    testWidgets('A sign-out closes the guarded page of a nested router under '
        'another page', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef.shell(
            name: 'ShellRoute',
            path: '/',
            children: [
              NamedRouteDef(
                name: 'ListRoute',
                path: '',
                builder: (_, _) => page('ListRoute'),
              ),
              NamedRouteDef(
                name: 'AccountRoute',
                path: 'account',
                guards: [
                  AutoRouteGuard.simple(
                    (resolver, _) =>
                        isSignedIn.value ? resolver.next() : resolver.reject(),
                  ),
                ],
                builder: (_, _) => page('AccountRoute'),
              ),
            ],
          ),
          NamedRouteDef(
            name: 'DetailsRoute',
            path: '/details',
            builder: (_, _) => page('DetailsRoute'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final inner = router.innerRouterOf<StackRouter>('ShellRoute');
      unawaited(inner?.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();
      expect(find.text('DetailsRoute'), findsOneWidget);

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      unawaited(router.maybePop());
      await tester.pumpAndSettle();

      expect(find.text('ListRoute'), findsOneWidget);
      expect(find.text('AccountRoute'), findsNothing);
      expect(inner?.stack.map((page) => page.name), ['ListRoute']);
    });

    // Steps: two shell pages each hold a nested router with a page behind a
    // guard that sends a signed-out user to a login page. Open the guarded
    // page in both, and Details over them. The session signs out, then signs
    // in again.
    // Was, when the nested routers were asked side by side: two login pages,
    // one over the other.
    // Should: one login page, as the routers are asked one after another and
    // the second guard is asked only once the first has answered. Signing in
    // closes it and Details shows again.
    testWidgets('A sign-out that two covered guards answer with a login page '
        'shows one login page', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      Widget page(String name) => Scaffold(body: SafeArea(child: Text(name)));
      final guard = AutoRouteGuard.simple((resolver, _) {
        if (isSignedIn.value) return resolver.next();
        unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
      });
      NamedRouteDef shell(String name, String path) => .shell(
        name: name,
        path: path,
        children: [
          NamedRouteDef(
            name: 'ListRoute',
            path: '',
            builder: (_, _) => page('ListRoute'),
          ),
          NamedRouteDef(
            name: 'AccountRoute',
            path: 'account',
            guards: [guard],
            builder: (_, _) => page('AccountRoute'),
          ),
        ],
      );
      final router = RootStackRouter.build(
        routes: [
          shell('ShellRoute', '/'),
          shell('OtherShellRoute', '/other'),
          NamedRouteDef(
            name: 'DetailsRoute',
            path: '/details',
            builder: (_, _) => page('DetailsRoute'),
          ),
          NamedRouteDef(
            name: 'LoginRoute',
            path: '/login',
            builder: (_, _) => page('LoginRoute'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final inner = router.innerRouterOf<StackRouter>('ShellRoute');
      unawaited(inner?.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(
        router.push(
          const NamedRoute(
            'OtherShellRoute',
            children: [NamedRoute('ListRoute'), NamedRoute('AccountRoute')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('DetailsRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'DetailsRoute');

      isSignedIn.value = false;
      await tester.pumpAndSettle();

      expect(find.text('LoginRoute'), findsOneWidget);
      expect(
        router.stack.where((page) => page.name == 'LoginRoute'),
        hasLength(1),
      );

      // Signing in asks the guards again, which closes the login page.
      isSignedIn.value = true;
      await tester.pumpAndSettle();

      expect(find.text('DetailsRoute'), findsOneWidget);
      expect(router.stack.map((page) => page.name), [
        'ShellRoute',
        'OtherShellRoute',
        'DetailsRoute',
      ]);
    });
  });
}
