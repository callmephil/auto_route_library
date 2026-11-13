import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A RedirectRoute whose target is only partly matched opens what that target
// opens by itself, not the page of its first segments.
// Steps: RedirectRoute(path: '/old-profile', redirectTo: '/profile/settings')
// where only '/profile' is a page, and RedirectRoute(path: 'legacy',
// redirectTo: 'users/5') among the children of /dash, where only 'users' is a
// page. Match each redirect's path, and its target, with and without a
// catch-all '*' page.
// Was: the redirect opened ProfileRoute and UsersRoute, while the target url
// opened by itself matched nothing, or the '*' page. A redirect returned the
// matches of its target before the check that a url is matched to its end.
// Native behavior this holds to: a redirect on the web (RFC 9110 section
// 15.4) loads its target as any url is loaded, so a target no page has gives
// the site's not-found page; Flutter's Navigator gives a name no route has to
// onUnknownRoute, never to the route of its first segments.
RootStackRouter _router({required bool hasCatchAll}) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'ProfileRoute',
      path: '/profile',
      builder: (_, _) => const Text('ProfileRoute'),
    ),
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
        RedirectRoute(path: 'legacy', redirectTo: 'users/5'),
        RedirectRoute(path: 'team', redirectTo: 'users'),
      ],
    ),
    RedirectRoute(path: '/old-profile', redirectTo: '/profile/settings'),
    RedirectRoute(path: '/me', redirectTo: '/profile'),
    if (hasCatchAll)
      NamedRouteDef(
        name: 'NotFoundRoute',
        path: '*',
        builder: (_, _) => const Text('NotFoundRoute'),
      ),
  ],
);

// The names of the matches from the top down, following the last child.
String? _namesOf(List<RouteMatch<Object?>>? matches) {
  final names = <String>[];
  var last = matches?.lastOrNull;
  while (last != null) {
    names.add(last.name);
    last = last.children?.lastOrNull;
  }
  return names.isEmpty ? null : names.join(' > ');
}

void main() {
  for (final hasCatchAll in [false, true]) {
    final notFound = hasCatchAll ? 'NotFoundRoute' : null;
    group(
      hasCatchAll ? 'With a catch-all page' : 'Without a catch-all page',
      () {
        for (final (link, target) in [
          ('/old-profile', '/profile/settings'),
          ('/dash/legacy', '/dash/users/5'),
        ]) {
          test('$link matches what $target matches', () {
            final matcher = _router(hasCatchAll: hasCatchAll).matcher;
            expect(
              (_namesOf(matcher.match(link)), _namesOf(matcher.match(target))),
              (notFound, notFound),
            );
          });
        }

        // A target matched to its end still opens, whatever its length.
        for (final (link, names) in [
          ('/me', 'ProfileRoute'),
          ('/dash/team', 'DashRoute > UsersRoute'),
        ]) {
          test('$link still opens its target', () {
            final matcher = _router(hasCatchAll: hasCatchAll).matcher;
            expect(_namesOf(matcher.match(link)), names);
          });
        }
      },
    );
  }

  // Steps: start the app at /dash/legacy, which redirects to /dash/users/5.
  // Should: the '*' page shows, as it does for /dash/users/5, not UsersRoute.
  testWidgets('An app started at a redirect to a path no page has shows the '
      'catch-all page', (tester) async {
    await pumpRouterApp(
      tester,
      _router(hasCatchAll: true),
      initialLink: '/dash/legacy',
    );
    expect(
      (
        find.text('NotFoundRoute').evaluate().length,
        find.text('UsersRoute').evaluate().length,
      ),
      (1, 0),
    );
  });
}
