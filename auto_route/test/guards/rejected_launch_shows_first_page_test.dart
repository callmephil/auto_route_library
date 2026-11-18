import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../named_page.dart';
import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// Steps: the app starts at '/g', whose guard says no, and no page of the app
// is under it (the web opens a link alone, so prefix matches are off). The
// guard answers at once, or later.
// The first page of the app should show, '/', and the url should be its own.
// Before, the root was left without a page: a black screen, and a first push
// became its only page.
// Native behavior: Flutter's Navigator.pages refuses an empty list, and a
// Navigator with no route opens its default route, '/'
// (navigator.dart `_debugCheckPageApiParameters`, `initState`). Android's
// NavController always has its start destination, and its docs name an empty
// back stack a blank screen to be resolved (developer.android.com/guide/
// navigation/backstack, "Handle a failed pop back"). An iOS navigation
// controller never has fewer than its root view controller (UIKit docs of
// popViewController(animated:): "you cannot pop the last item on the stack").
// A browser keeps the document on screen when a navigation is canceled.
void main() {
  RootStackRouter build({required AutoRouteGuard guard}) => .build(
    routes: [
      NamedRouteDef(
        name: 'H',
        path: '/',
        builder: (_, _) => const NamedPage('H'),
      ),
      NamedRouteDef(
        name: 'G',
        path: '/g',
        guards: [guard],
        builder: (_, _) => const NamedPage('G'),
      ),
      NamedRouteDef(
        name: 'X',
        path: '/x',
        builder: (_, _) => const NamedPage('X'),
      ),
    ],
  );

  Future<void> launchAt(
    WidgetTester tester,
    RootStackRouter router, {
    String link = '/g',
  }) async {
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    dispatcher.defaultRouteNameTestValue = link;
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );
  }

  for (final slow in [false, true]) {
    testWidgets('a guard saying no ${slow ? 'later' : 'at once'} to the '
        'launch link leaves the first page', (tester) async {
      final guard = HeldGuard(mode: slow ? .holdsCall : .answersNo);
      final router = build(guard: guard);
      await launchAt(tester, router);
      if (slow) await guard.last.reject();
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.name), ['H']);
      expect(find.text('H'), findsOneWidget);
      expect(find.text('G'), findsNothing);
      expect(router.urlState.url, '/');
      // A push goes over the first page, not in its place.
      unawaited(router.push(const NamedRoute('X')));
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.name), ['H', 'X']);
    });
  }

  testWidgets('the first page is the one marked initial, not only "/"', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'H',
          path: '/home',
          initial: true,
          builder: (_, _) => const NamedPage('H'),
        ),
        NamedRouteDef(
          name: 'G',
          path: '/g',
          guards: [HeldGuard(mode: .answersNo)],
          builder: (_, _) => const NamedPage('G'),
        ),
      ],
    );
    await launchAt(tester, router);
    expect(router.stack.map((page) => page.name), ['H']);
    expect(find.text('H'), findsOneWidget);
  });

  // Collects the errors the router reports while [run] runs.
  Future<List<FlutterErrorDetails>> collectErrors(
    Future<void> Function() run,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await run();
    } finally {
      FlutterError.onError = onError;
    }
    return errors;
  }

  // Case A. Steps: the app has a global guard (RootStackRouter.guards) that
  // says no to '/g' and yes to every other route; it starts at '/g'.
  // Should: the first page shows, and the global guard is asked once for each
  // route, '/g' and '/'. Before, the root stayed empty.
  testWidgets('with a global guard, the first page shows and the guard is '
      'asked once for each route', (tester) async {
    final asked = <String>[];
    final router = RootStackRouter.build(
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          asked.add(resolver.routeName);
          if (resolver.routeName == 'G') return resolver.reject();
          resolver.next();
        }),
      ],
      routes: [
        NamedRouteDef(
          name: 'H',
          path: '/',
          builder: (_, _) => const NamedPage('H'),
        ),
        NamedRouteDef(
          name: 'G',
          path: '/g',
          builder: (_, _) => const NamedPage('G'),
        ),
      ],
    );
    await launchAt(tester, router);
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.name), ['H']);
    expect(find.text('H'), findsOneWidget);
    expect(router.urlState.url, '/');
    expect(asked, ['G', 'H']);
  });

  // Case B. Steps: the app starts at '/g', whose guard says no, and the first
  // page '/' has a guard of its own that sends the user to '/login'.
  // Should: the login page shows, as the guard of the first page decides, and
  // that guard is asked once. Before, the root stayed empty.
  testWidgets('a first page with a guard of its own shows what that guard '
      'decides, its redirect', (tester) async {
    final homeGuard = HeldGuard(mode: .returnsAtOnce);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'H',
          path: '/',
          guards: [homeGuard],
          builder: (_, _) => const NamedPage('H'),
        ),
        NamedRouteDef(
          name: 'G',
          path: '/g',
          guards: [HeldGuard(mode: .answersNo)],
          builder: (_, _) => const NamedPage('G'),
        ),
        NamedRouteDef(
          name: 'Login',
          path: '/login',
          builder: (_, _) => const NamedPage('Login'),
        ),
      ],
    );
    await launchAt(tester, router);
    await tester.pump();
    expect(homeGuard.askCount, 1);
    unawaited(homeGuard.last.redirectUntil(const NamedRoute('Login')));
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.name), ['Login']);
    expect(find.text('Login'), findsOneWidget);
    expect(homeGuard.askCount, 1);
  });

  // Case B with a guard that says no and shows nothing: no page is left.
  // Flutter's Navigator refuses an empty pages list with an error
  // (navigator.dart `_debugCheckPageApiParameters`: "The Navigator.pages must
  // not be empty"), so the router reports an error in place of a silent blank
  // screen. It does not open the first page against its guard: the guard
  // protects it.
  for (final link in ['/g', '/']) {
    testWidgets('when the first page says no too, from $link, the app reports '
        'no page to show and asks each guard once', (tester) async {
      final homeGuard = HeldGuard(mode: .answersNo);
      final otherGuard = HeldGuard(mode: .answersNo);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'H',
            path: '/',
            guards: [homeGuard],
            builder: (_, _) => const NamedPage('H'),
          ),
          NamedRouteDef(
            name: 'G',
            path: '/g',
            guards: [otherGuard],
            builder: (_, _) => const NamedPage('G'),
          ),
        ],
      );
      final errors = await collectErrors(
        () => launchAt(tester, router, link: link),
      );
      expect(router.stack, isEmpty);
      expect(errors, hasLength(1));
      expect(
        errors.singleOrNull?.exception.toString(),
        contains('The app launched with no page to show.'),
      );
      expect(homeGuard.askCount, 1);
      expect(otherGuard.askCount, link == '/g' ? 1 : 0);
    });
  }

  // Steps: the app starts at '/g' with a global guard that redirects every
  // route to '/login', '/login' included. Should: the loop is reported once,
  // and the first page is not opened to repeat it.
  testWidgets('a global guard redirecting in a loop reports it once', (
    tester,
  ) async {
    var asks = 0;
    final router = RootStackRouter.build(
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          if (++asks > 20) return;
          unawaited(resolver.redirectUntil(const NamedRoute('Login')));
        }),
      ],
      routes: [
        NamedRouteDef(
          name: 'H',
          path: '/',
          builder: (_, _) => const NamedPage('H'),
        ),
        NamedRouteDef(
          name: 'G',
          path: '/g',
          builder: (_, _) => const NamedPage('G'),
        ),
        NamedRouteDef(
          name: 'Login',
          path: '/login',
          builder: (_, _) => const NamedPage('Login'),
        ),
      ],
    );
    final errors = await collectErrors(() => launchAt(tester, router));
    expect(errors, hasLength(1));
    expect(
      errors.singleOrNull?.exception.toString(),
      contains('A guard redirected Login to itself.'),
    );
    expect(asks, 2);
  });

  testWidgets('a guard that opens a page of its own keeps it, and the first '
      'page does not come in its place', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'H',
          path: '/',
          builder: (_, _) => const NamedPage('H'),
        ),
        NamedRouteDef(
          name: 'G',
          path: '/g',
          guards: [
            AutoRouteGuard.simple((resolver, guardedRouter) {
              resolver.reject();
              unawaited(guardedRouter.push(const NamedRoute('X')));
            }),
          ],
          builder: (_, _) => const NamedPage('G'),
        ),
        NamedRouteDef(
          name: 'X',
          path: '/x',
          builder: (_, _) => const NamedPage('X'),
        ),
      ],
    );
    await launchAt(tester, router);
    expect(router.stack.map((page) => page.name), ['X']);
  });
}
