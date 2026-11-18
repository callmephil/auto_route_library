import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import '../named_page.dart';
import '../router_test_utils.dart';
import '../utils/held_guard.dart';

// Steps: the app starts at '/g', whose guard says no, and no page of the app
// is under it (the web opens a link alone, so prefix matches are off). The
// guard answers at once, or later.
// Should: the first page of the app shows, '/', and the url is its own. Before,
// the root was left without a page: a black screen, and a first push became
// its only page.
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
  RootStackRouter build({
    required AutoRouteGuard guard,
    bool isGuardedFirst = false,
    bool hasPlainFirst = true,
  }) => RootStackRouter.build(
    routes: [
      if (hasPlainFirst)
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
      final guard = HeldGuard(
        mode: slow ? HeldGuardMode.holdsCall : HeldGuardMode.answersNo,
      );
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
          guards: [HeldGuard(mode: HeldGuardMode.answersNo)],
          builder: (_, _) => const NamedPage('G'),
        ),
      ],
    );
    await launchAt(tester, router);
    expect(router.stack.map((page) => page.name), ['H']);
    expect(find.text('H'), findsOneWidget);
  });

  testWidgets('when the first page says no too, the root stays empty and the '
      'app asks it once', (tester) async {
    final guard = HeldGuard(mode: HeldGuardMode.answersNo);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'H',
          path: '/',
          guards: [guard],
          builder: (_, _) => const NamedPage('H'),
        ),
      ],
    );
    await launchAt(tester, router, link: '/');
    expect(router.stack, isEmpty);
    expect(guard.askCount, 1);
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
            AutoRouteGuard.simple((resolver, router) {
              resolver.reject();
              unawaited(router.push(const NamedRoute('X')));
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
