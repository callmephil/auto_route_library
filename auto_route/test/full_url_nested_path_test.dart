import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A url with a scheme and host given to navigatePath opens a nested page as
// it opens a top-level one: by its path alone.
// Steps: navigatePath('https://example.com/dashboard/users'), where
// '/dashboard' has the child 'users'.
// Was: RouteNotFoundFailure, while 'https://example.com/report' opened Report:
// for the rest of the path after a parent, the matcher kept the host, and
// Dart starts the path of a uri with a host with '/', so the children were
// matched against '/users'. The README still tells apps to drop the scheme
// and host first; this keeps the same url working at every level.
// Native behavior this holds to: the package's rule that a page is matched by
// the path alone (unusual_links_test.dart), as Flutter's router hands a link
// to the parser whatever its host.
RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Text('HomeRoute'),
    ),
    NamedRouteDef(
      name: 'ReportRoute',
      path: '/report',
      builder: (_, _) => const Text('ReportRoute'),
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
      ],
    ),
  ],
);

void main() {
  for (final (url, page) in [
    ('https://example.com/report', 'ReportRoute'),
    ('/dashboard/users', 'UsersRoute'),
    ('https://example.com/dashboard/users', 'UsersRoute'),
  ]) {
    testWidgets('navigatePath("$url") opens $page', (tester) async {
      final router = _router();
      await pumpRouterConfigApp(tester, router.config());
      RouteNotFoundFailure? notFound;
      unawaited(
        router.navigatePath(
          url,
          onFailure: (failure) => notFound = failure as RouteNotFoundFailure,
        ),
      );
      await tester.pumpAndSettle();
      expect(notFound, isNull);
      expect(find.text(page), findsOneWidget);
    });
  }
}
