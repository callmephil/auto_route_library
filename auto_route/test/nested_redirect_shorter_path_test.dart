import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A RedirectRoute among a route's children whose target is shorter than the
// path it matches opens its target from a link.
// Steps: the app runs on '/'; the platform hands it a link under /dash, whose
// children hold RedirectRoute(path: 'old/users', redirectTo: 'users') and the
// catch-all RedirectRoute(path: '*', redirectTo: '').
// Was: /dash/old/users and /dash/zzz/yyy matched nothing and showed no page:
// the matcher counted the segments of the page the redirect ended on, not
// the segments the redirect took from the url. A top-level redirect, a nested
// one of equal length and the catch-all for one segment worked.
// Native behavior this holds to: a redirect on the web (RFC 9110 section
// 15.4) replaces the url whatever the lengths of the two paths, and the
// README's "Redirecting Paths" and "Wildcards" set no such limit.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'DashRoute',
      path: '/dash',
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
        RedirectRoute(path: '*', redirectTo: ''),
      ],
    ),
    RedirectRoute(path: '/legacy/dash/users', redirectTo: '/dash/users'),
  ],
);

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

void main() {
  for (final (link, page, url) in [
    ('/legacy/dash/users', 'UsersRoute', '/dash/users'),
    ('/dash/member/7', 'User 7', '/dash/users/7'),
    ('/dash/zzz', 'OverviewRoute', '/dash'),
    ('/dash/old/users', 'UsersRoute', '/dash/users'),
    ('/dash/zzz/yyy', 'OverviewRoute', '/dash'),
  ]) {
    testWidgets('The link $link opens $url', (tester) async {
      final router = _router();
      expect(
        router.matcher.match(link),
        isNotNull,
        reason: 'the matcher finds no route for $link',
      );

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

  test('A path no child has still matches nothing without a catch-all', () {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'DashRoute',
          path: '/dash',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'UsersRoute',
              path: 'users',
              builder: (_, _) => const Text('UsersRoute'),
            ),
            RedirectRoute(path: 'old/users', redirectTo: 'users'),
          ],
        ),
      ],
    );
    expect(router.matcher.match('/dash/old/users/extra'), isNull);
    expect(router.matcher.match('/dash/users/extra'), isNull);
  });
}
