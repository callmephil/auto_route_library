import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'named_page.dart';
import 'router_test_utils.dart';

// A navigation through the root that names children for the nested router
// or the tabs of an open page reached them some microtasks after the call,
// also when no guard was asked. A call made right after it, in the same
// handler with no await between them, acted on them as they were.
// Steps, nested router: the shell shows [A]. Call
// router.navigate(ShellRoute(children: [BRoute()])) and then inner.push(C)
// or inner.replace(C).
// Was: [A, C, B] and [C, B]. Should: [A, B, C] and [A, C].
// Steps, tabs: the Feed tab shows. Call router.navigatePath('/profile') and
// then tabs.setActiveIndex(0).
// Was: the Profile tab shows. Should: the Feed tab, the later call.
// Native behavior this holds to: Flutter's Navigator changes its history as
// each call is made, for a nested Navigator as for the root one, so a push
// on a nested Navigator right after one that put a route on it lands above
// that route. A TabController's index is the one set last
// (tab_controller.dart, _changeIndex).
void main() {
  List<String> stackNames(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  NamedRouteDef page(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => NamedPage(name),
  );

  const shellWithB = NamedRoute('ShellRoute', children: [NamedRoute('BRoute')]);
  const c = NamedRoute('CRoute');

  group('A nested router', () {
    // Opens the shell at '/', whose nested router shows [A].
    Future<(RootStackRouter, StackRouter)> open(
      WidgetTester tester, {
      List<AutoRouteGuard> guardsOfB = const [],
    }) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'ShellRoute',
            path: '/',
            builder: (_, _) => const AutoRouter(),
            children: [
              page('ARoute', ''),
              page('BRoute', 'b', guards: guardsOfB),
              page('CRoute', 'c'),
            ],
          ),
          page('SettingsRoute', '/settings'),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      return (router, router.innerRouterOf<StackRouter>('ShellRoute')!);
    }

    testWidgets('shows the child of navigate as the call returns', (
      tester,
    ) async {
      final (router, inner) = await open(tester);

      unawaited(router.navigate(shellWithB));

      expect(stackNames(inner), ['ARoute', 'BRoute']);
      expect(router.currentUrl, '/b');

      await tester.pumpAndSettle();

      expect(find.text('BRoute'), findsOneWidget);
    });

    testWidgets('puts a push right after navigate with a child above the '
        'child', (tester) async {
      final (router, inner) = await open(tester);

      unawaited(router.navigate(shellWithB));
      unawaited(inner.push(c));
      await tester.pumpAndSettle();

      expect(stackNames(inner), ['ARoute', 'BRoute', 'CRoute']);
      expect(find.text('CRoute'), findsOneWidget);
    });

    testWidgets('replaces the child with a replace right after navigate', (
      tester,
    ) async {
      final (router, inner) = await open(tester);

      unawaited(router.navigate(shellWithB));
      unawaited(inner.replace(c));
      await tester.pumpAndSettle();

      expect(stackNames(inner), ['ARoute', 'CRoute']);
      expect(find.text('CRoute'), findsOneWidget);
    });

    // Steps: push Settings over the shell, then navigate back to the shell
    // with a child.
    // Should: Settings is off and the child is on as the call returns.
    testWidgets('shows the child as navigate returns to its page from '
        'another', (tester) async {
      final (router, inner) = await open(tester);
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();

      unawaited(router.navigate(shellWithB));

      expect(stackNames(router), ['ShellRoute']);
      expect(stackNames(inner), ['ARoute', 'BRoute']);

      await tester.pumpAndSettle();

      expect(find.text('BRoute'), findsOneWidget);
    });

    // Should: the kept shell shows the child replaceAll names as the call
    // returns, so a push right after it lands above the child.
    testWidgets('shows the child of replaceAll as the call returns', (
      tester,
    ) async {
      final (router, inner) = await open(tester);

      unawaited(router.replaceAll([shellWithB]));

      expect(stackNames(inner), ['BRoute']);

      unawaited(inner.push(c));
      await tester.pumpAndSettle();

      expect(stackNames(inner), ['BRoute', 'CRoute']);
      expect(find.text('CRoute'), findsOneWidget);
    });

    // A child whose guard awaits makes its own page wait. A call made
    // meanwhile does not wait behind it, as in the router that is called.
    // Should: the push goes on at once, and the child above it once its guard
    // lets it through.
    testWidgets('does not hold a push behind a child whose guard awaits', (
      tester,
    ) async {
      final (router, inner) = await open(
        tester,
        guardsOfB: [
          AutoRouteGuard.simple((resolver, _) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            resolver.next();
          }),
        ],
      );

      unawaited(router.navigate(shellWithB));
      unawaited(inner.push(c));

      expect(stackNames(inner), ['ARoute', 'CRoute']);

      await tester.pumpAndSettle();

      expect(stackNames(inner), ['ARoute', 'CRoute', 'BRoute']);
    });
  });

  group('Tabs', () {
    // Opens tabs at '/', Feed and Profile. Profile holds a nested router
    // that shows its home page; ProfileEditRoute is its second page.
    Future<(RootStackRouter, TabsRouter)> open(WidgetTester tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const AutoTabsRouter(
              routes: [NamedRoute('FeedRoute'), NamedRoute('ProfileRoute')],
            ),
            children: [
              page('FeedRoute', 'feed'),
              NamedRouteDef(
                name: 'ProfileRoute',
                path: 'profile',
                builder: (_, _) => const AutoRouter(),
                children: [
                  page('ProfileHomeRoute', ''),
                  page('ProfileEditRoute', 'edit'),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      return (router, router.innerRouterOf<TabsRouter>('HomeRoute')!);
    }

    testWidgets('show the tab of navigatePath as the call returns', (
      tester,
    ) async {
      final (router, tabs) = await open(tester);

      unawaited(router.navigatePath('/profile'));

      expect(tabs.activeIndex, 1);

      await tester.pumpAndSettle();

      expect(find.text('ProfileHomeRoute'), findsOneWidget);
    });

    testWidgets('show the tab navigate names as a child as the call returns', (
      tester,
    ) async {
      final (router, tabs) = await open(tester);

      unawaited(
        router.navigate(
          const NamedRoute('HomeRoute', children: [NamedRoute('ProfileRoute')]),
        ),
      );

      expect(tabs.activeIndex, 1);

      await tester.pumpAndSettle();

      expect(find.text('ProfileHomeRoute'), findsOneWidget);
    });

    testWidgets('end on the tab of setActiveIndex called right after '
        'navigatePath', (tester) async {
      final (router, tabs) = await open(tester);

      unawaited(router.navigatePath('/profile'));
      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();

      expect(tabs.activeIndex, 0);
      expect(find.text('FeedRoute'), findsOneWidget);
    });

    // Steps: show the Profile tab once, go back to Feed, then call
    // navigatePath('/profile/edit') on the root.
    // Should: as the call returns, the Profile tab is the active one and its
    // nested router holds the edit page.
    testWidgets('and the nested router of the tab show a path through both '
        'as the call returns', (tester) async {
      final (router, tabs) = await open(tester);
      tabs.setActiveIndex(1);
      await tester.pumpAndSettle();
      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();
      final profile = tabs.innerRouterOf<StackRouter>('ProfileRoute')!;

      unawaited(router.navigatePath('/profile/edit'));

      expect(tabs.activeIndex, 1);
      expect(stackNames(profile), ['ProfileHomeRoute', 'ProfileEditRoute']);

      await tester.pumpAndSettle();

      expect(find.text('ProfileEditRoute'), findsOneWidget);
    });
  });
}
