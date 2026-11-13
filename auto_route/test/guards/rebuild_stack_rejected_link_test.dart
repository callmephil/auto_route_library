import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
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
        ('WelcomeRoute', '/welcome'),
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
    expect(router.currentUrl, '/details');
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

  // Prefix matches are on by default off the web and off by default on it,
  // where the browser's url names every page; the link names Home as well
  // only with them.
  for (final includePrefixMatches in [true, false]) {
    testWidgets('A link the guards let in replaces the stack, with prefix '
        'matches ${includePrefixMatches ? 'on' : 'off'}', (tester) async {
      final router = buildRouter();
      await pumpRouterConfigApp(
        tester,
        router.config(
          rebuildStackOnDeepLink: true,
          includePrefixMatches: includePrefixMatches,
        ),
      );
      await openDetails(tester, router);

      await tester.binding.handlePushRoute('/other');
      await tester.pumpAndSettle();

      expect(stackNames(router), [
        if (includePrefixMatches) 'HomeRoute',
        'OtherRoute',
      ]);
      expect(find.text('OtherRoute'), findsOneWidget);
      expect(router.currentUrl, '/other');
    });
  }

  // A guard that shows a page of its own, here a sign-in page with
  // redirectUntil, shows it over the open pages: they are the user's own,
  // which the link found. A link let in replaces them in one step; one the
  // guard rejects leaves them. With prefix matches on, on the web too, the
  // link names Home below its page.
  for (final isLetIn in [true, false]) {
    testWidgets(
      'A link whose guard shows a sign-in page '
      '${isLetIn ? 'replaces the stack once let in' : 'keeps the stack when rejected after it'}',
      (tester) async {
        final router = buildRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            includePrefixMatches: true,
          ),
        );
        await openDetails(tester, router);

        await tester.binding.handlePushRoute('/account');
        await tester.pumpAndSettle();
        expect(stackNames(router), ['HomeRoute', 'DetailsRoute', 'OtherRoute']);

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

  // Found while proving a lead of the second audit of the library.
  // Steps: a link whose guard shows a sign-in page shows it over the open
  // pages. A second link comes in and a guard rejects it. Then the first
  // link's guard rejects, as when the user cancels the sign-in.
  // Was: no page was left. The first link stopped as one a later link had
  // taken over, without the step that brings back the pages its guard's
  // page had taken the place of.
  // Should: the open pages are back, as after the same rejection with no
  // second link: a refused navigation changes nothing.
  testWidgets('The pages come back when a second, rejected link came in '
      'while the sign-in page of a link was open', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await openDetails(tester, router);

    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    final atSignIn = stackNames(router);
    final firstLink = signingIn;
    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();
    firstLink?.reject();
    await tester.pumpAndSettle();

    expect(atSignIn, ['HomeRoute', 'DetailsRoute', 'OtherRoute']);
    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
    expect(find.text('DetailsRoute'), findsOneWidget);
  });

  // Found by the review of the batch's links (Part 5); dev had [Home, Login].
  // Steps: a link whose guard shows a sign-in page; the user goes back from
  // it, with the Android back key or the back button.
  // Was: the sign-in page was the only page, so back closed nothing and on
  // Android the back key closed the app.
  // Should: back leaves the sign-in page, which rejects the link, and the
  // pages the user had open show again, with their url.
  // Native behavior this holds to: back from a screen a link opened shows
  // the app under it, on Android (the task's back stack) and on iOS.
  testWidgets('Back from the sign-in page of a link shows the pages that '
      'were open', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await openDetails(tester, router);

    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    expect(find.text('OtherRoute'), findsOneWidget);
    expect(router.canPop(), isTrue);

    await systemBack(tester);

    expect(stackNames(router), ['HomeRoute', 'DetailsRoute']);
    expect(find.text('DetailsRoute'), findsOneWidget);
    expect(router.currentUrl, '/details');
  });

  // Found by the second audit of the library (L2-4, its link form).
  // Steps: a link whose guard shows a sign-in page over the open pages; the
  // sign-in page then replaces the stack itself, as a "continue as guest"
  // button or a sign-in handler that calls replaceAll does.
  // Should: only the new page is left. The guard's redirect ends with its
  // page, which rejects the link, and the open pages must not come back
  // under the new one.
  // Native behavior this holds to: replaceAll leaves only its own pages, as
  // an Android start with FLAG_ACTIVITY_CLEAR_TASK does and as iOS
  // setViewControllers drops every controller not in the new array.
  testWidgets('A sign-in page that replaces the stack leaves only its new '
      'page', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true),
    );
    await openDetails(tester, router);
    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    expect(find.text('OtherRoute'), findsOneWidget);

    unawaited(router.replaceAll([const NamedRoute('WelcomeRoute')]));
    await tester.pumpAndSettle();

    expect(stackNames(router), ['WelcomeRoute']);
    expect(find.text('WelcomeRoute'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });
}
