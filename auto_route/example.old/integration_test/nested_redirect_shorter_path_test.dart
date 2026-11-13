import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A RedirectRoute among a route's children whose target is shorter than the
// path it matches opens its target from a link, and the url names it.
// Headless test: auto_route/test/nested_redirect_shorter_path_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('nested redirect to a shorter path', () {
    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
        ),
        NamedRouteDef(
          name: 'DashRoute',
          path: '/dash',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'OverviewRoute',
              path: '',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('OverviewRoute'))),
            ),
            NamedRouteDef(
              name: 'UsersRoute',
              path: 'users',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('UsersRoute'))),
            ),
            RedirectRoute(path: 'old/users', redirectTo: 'users'),
            RedirectRoute(path: '*', redirectTo: ''),
          ],
        ),
      ],
    );

    // Steps: start the app at the link.
    // Was: no page showed for either link.
    // Should: the redirect's target shows, and the url is the target's.
    for (final (link, page, url) in [
      ('/dash/old/users', 'UsersRoute', '/dash/users'),
      ('/dash/zzz/yyy', 'OverviewRoute', '/dash'),
    ]) {
      testWidgets('An app started at $link opens $url', (tester) async {
        final app = router();
        await pumpAppAtDeepLink(
          tester,
          link,
          // Made inside the app, so the config reads the link.
          Builder(
            builder: (_) => MaterialApp.router(routerConfig: app.config()),
          ),
        );

        expect(find.text(page), findsOneWidget);
        expect(app.currentUrl, url);
        await expectBrowserUrl(url);
      });
    }
  });
}
