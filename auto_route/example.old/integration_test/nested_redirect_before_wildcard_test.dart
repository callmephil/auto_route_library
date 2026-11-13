import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A nested redirect to a shorter path, and the nested catch-all, win over the
// app's own '*' not-found page declared after their parent.
// Headless test: auto_route/test/nested_redirect_before_wildcard_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('nested redirect before a not-found page', () {
    Widget page(String text) => Scaffold(body: SafeArea(child: Text(text)));

    RootStackRouter router() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => page('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'DashboardRoute',
          path: '/dashboard',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'OverviewRoute',
              path: '',
              builder: (_, _) => page('OverviewRoute'),
            ),
            NamedRouteDef(
              name: 'UsersRoute',
              path: 'users',
              builder: (_, _) => page('UsersRoute'),
            ),
            RedirectRoute(path: 'old/users', redirectTo: 'users'),
            RedirectRoute(path: '*', redirectTo: ''),
          ],
        ),
        NamedRouteDef(
          name: 'UnknownRoute',
          path: '*',
          builder: (_, _) => page('UnknownRoute'),
        ),
      ],
    );

    // Steps: start the app at the link.
    // Was: the not-found page showed.
    // Should: the redirect's target shows, and the url is the target's.
    for (final (link, shown, url) in [
      ('/dashboard/old/users', 'UsersRoute', '/dashboard/users'),
      ('/dashboard/zzz/yyy', 'OverviewRoute', '/dashboard'),
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

        expect(
          (
            find.text(shown).evaluate().length,
            find.text('UnknownRoute').evaluate().length,
            app.currentUrl,
          ),
          (1, 0, url),
        );
        await expectBrowserUrl(url);
      });
    }
  });
}
