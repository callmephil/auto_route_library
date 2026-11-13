import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// With rebuildStackOnDeepLink, a link a guard rejected still closed the pages
// the user had open, and the url then named the rejected link: the delegate
// popped the whole stack before the link's guards ran, and nothing put it
// back. The link's pages now replace the stack as replaceAll does, once the
// guards let them in.
// Steps: config(rebuildStackOnDeepLink: true); open Home, push Details. The
// platform hands the app a link to a page whose guard rejects it, or one
// deepLinkBuilder turns into such a path; or a link the guards let in.
// Native behavior this holds to: a navigation that is refused changes
// nothing: on the web a canceled navigation leaves the url and the current
// entry, and Android applies a task's new back stack only when the activity
// the link opens starts.
void main() {
  // The resolver of the guard that sends the user to sign in first.
  NavigationResolver? signingIn;
  setUp(() => signingIn = null);

  RootStackRouter buildRouter() => .build(
    routes: [
      for (final (name, path) in [
        ('HomeRoute', '/'),
        ('DetailsRoute', '/details'),
        ('OtherRoute', '/other'),
      ])
        NamedRouteDef(
          name: name,
          path: path,
          builder: (_, _) => Scaffold(body: Text(name)),
        ),
      NamedRouteDef(
        name: 'AccountRoute',
        path: '/account',
        guards: [
          AutoRouteGuard.simple((resolver, _) {
            signingIn = resolver;
            unawaited(resolver.redirectUntil(const NamedRoute('OtherRoute')));
          }),
        ],
        builder: (_, _) => const Scaffold(body: Text('AccountRoute')),
      ),
      NamedRouteDef(
        name: 'GuardedRoute',
        path: '/guarded',
        guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
        builder: (_, _) => const Scaffold(body: Text('GuardedRoute')),
      ),
    ],
  );

  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  Future<void> openDetails(WidgetTester tester, StackRouter router) async {
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
  }

  testWidgets('A rejected link keeps the stack when rebuildStackOnDeepLink '
      'is on', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await openDetails(tester, router);

    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
    expect(find.text('DetailsRoute'), findsOneWidget);
  });

  testWidgets('A link deepLinkBuilder turns into a rejected path keeps the '
      'stack', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(
        rebuildStackOnDeepLink: true,
        deepLinkBuilder: (link) =>
            link.initial ? link : const DeepLink.path('/guarded'),
      ),
    );
    await openDetails(tester, router);

    await tester.binding.handlePushRoute('/other');
    await tester.pumpAndSettle();

    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
    expect(find.text('DetailsRoute'), findsOneWidget);
  });

  testWidgets('A link the guards let in replaces the stack', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await openDetails(tester, router);

    await tester.binding.handlePushRoute('/other');
    await tester.pumpAndSettle();

    // With prefix matches, the default off the web, the link names Home too.
    expect(stackNames(router), ['HomeRoute', 'OtherRoute']);
    expect(find.text('OtherRoute'), findsOneWidget);
    expect(router.currentUrl, '/other');
  });

  // A guard that shows a page of its own, here a sign-in page with
  // redirectUntil, puts it in the place of the open pages, as replaceAll
  // does; they come back if the guard then rejects the link.
  for (final isLetIn in [true, false]) {
    testWidgets(
      'A link whose guard shows a sign-in page '
      '${isLetIn ? 'replaces the stack once let in' : 'keeps the stack when rejected after it'}',
      (tester) async {
        final router = buildRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(rebuildStackOnDeepLink: true),
        );
        await openDetails(tester, router);

        await tester.binding.handlePushRoute('/account');
        await tester.pumpAndSettle();
        expect(stackNames(router), ['OtherRoute']);

        isLetIn ? signingIn!.next() : signingIn!.reject();
        await tester.pumpAndSettle();

        if (isLetIn) {
          expect(stackNames(router), ['HomeRoute', 'AccountRoute']);
          expect(router.currentUrl, '/account');
        } else {
          expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
          expect(find.text('DetailsRoute'), findsOneWidget);
          expect(router.currentUrl, '/details');
        }
      },
    );
  }
}
