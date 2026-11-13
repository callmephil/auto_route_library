import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A RedirectRoute among a route's children whose target is shorter than its
// path, and the nested catch-all, win over a route declared after their
// parent, such as the app's own '*' not-found page.
// Steps: the README's routes for a nested redirect ('/dashboard' with the
// children 'users' and RedirectRoute(path: 'old/users', redirectTo: 'users'))
// plus the README's not-found page, AutoRoute(path: '*'), as the last route.
// The app runs on '/'; the platform hands it /dashboard/old/users.
// Was: the not-found page opened; with '/:language' as the last route the
// link matched nothing. The loop over the routes stopped after a parent only
// when the segments of the page a redirect ended on covered the url, not the
// segments the redirect took, so a later route took the url. Found by the
// second audit (U2-2); it is where the fix of a nested redirect to a shorter
// path stopped.
// Native behavior this holds to: routes are matched in order, and the first
// one that takes the whole url wins (README, "Wildcards"); a web server's
// redirect rule listed before its catch-all rule runs first whatever the
// length of its target (RFC 9110 section 15.4).
RootStackRouter _router({required List<AutoRoute> after}) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'DashboardRoute',
      path: '/dashboard',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'OverviewRoute',
          path: '',
          builder: (_, _) => const Text('OverviewRoute'),
        ),
        NamedRouteDef(
          name: 'UsersRoute',
          path: 'users',
          builder: (_, _) => const Text('UsersRoute'),
        ),
        NamedRouteDef(
          name: 'UserRoute',
          path: 'users/:id',
          builder: (_, data) => Text('User ${data.params.getString('id')}'),
        ),
        RedirectRoute(path: 'member/:id', redirectTo: 'users/:id'),
        RedirectRoute(path: 'old/users', redirectTo: 'users'),
        RedirectRoute(path: 'old/pages/users/:id', redirectTo: 'users/:id'),
        RedirectRoute(path: '*', redirectTo: ''),
      ],
    ),
    ...after,
  ],
);

List<AutoRoute> _notFound() => [
  NamedRouteDef(
    name: 'UnknownRoute',
    path: '*',
    builder: (_, _) => const Text('UnknownRoute'),
  ),
];

List<AutoRoute> _languageHome() => [
  NamedRouteDef(
    name: 'LanguageRoute',
    path: '/:language',
    builder: (_, data) => Text('Language ${data.params.getString('language')}'),
  ),
];

// Hands [location] to the running app the way the engine does when the
// platform opens a link.
Future<void> _sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

const _links = [
  // Controls: a target as long as the redirect's path, and a known page.
  ('/dashboard/member/7', 'User 7', '/dashboard/users/7'),
  ('/dashboard/users', 'UsersRoute', '/dashboard/users'),
  // A target shorter than the redirect's path.
  ('/dashboard/old/users', 'UsersRoute', '/dashboard/users'),
  ('/dashboard/old/pages/users/7', 'User 7', '/dashboard/users/7'),
  // The nested catch-all, declared before the top-level one.
  ('/dashboard/zzz', 'OverviewRoute', '/dashboard'),
  ('/dashboard/zzz/yyy', 'OverviewRoute', '/dashboard'),
];

void main() {
  group('Control, no route after the parent:', () {
    for (final (link, page, url) in _links) {
      testWidgets('the link $link opens $url', (tester) async {
        final router = _router(after: const []);
        await pumpRouterConfigApp(
          tester,
          router.config(includePrefixMatches: false),
        );
        await _sendPlatformLink(tester, link);
        await tester.pumpAndSettle();
        expect(find.text(page), findsOneWidget);
        expect(router.currentUrl, url);
      });
    }
  });

  group("With the app's '*' not-found page as the last route:", () {
    for (final (link, page, url) in _links) {
      testWidgets('the link $link opens $url', (tester) async {
        final router = _router(after: _notFound());
        await pumpRouterConfigApp(
          tester,
          router.config(includePrefixMatches: false),
        );
        await _sendPlatformLink(tester, link);
        await tester.pumpAndSettle();
        expect(find.text('UnknownRoute'), findsNothing);
        expect(find.text(page), findsOneWidget);
        expect(router.currentUrl, url);
      });
    }

    testWidgets('a url no route has still opens the not-found page', (
      tester,
    ) async {
      final router = _router(after: _notFound());
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: false),
      );
      await _sendPlatformLink(tester, '/nowhere/at/all');
      await tester.pumpAndSettle();
      expect(find.text('UnknownRoute'), findsOneWidget);
    });
  });

  group("With a '/:language' page as the last route:", () {
    for (final (link, page, url) in _links) {
      test('the matcher finds $url for $link', () {
        final router = _router(after: _languageHome());
        addTearDown(router.dispose);
        final matches = router.matcher.match(link) ?? const [];
        expect(
          (
            matches.lastOrNull?.name,
            UrlState.fromSegments(matches).flatten.url,
          ),
          ('DashboardRoute', url),
          reason: page,
        );
      });
    }
  });
}
