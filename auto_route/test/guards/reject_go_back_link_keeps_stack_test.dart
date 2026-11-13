import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A link with a query or a fragment that a guard turns down with
// reject(goBack: true) put the page on screen on the stack a second time.
// Found by the audit of auto_route/lib at dev 56b73492 (finding C18), a
// regression of 50534c5d.
// Setup: off the web, where a link comes with the pages below it
// (includePrefixMatches). SecretRoute's guard calls
// resolver.reject(goBack: true).
// Steps: open Home, push<int> Other and wait for its result, then the platform
// hands the running app the link /secret?x=1 (or /secret#top).
// Was: Flutter's duplicate page key assertion in debug builds; in release
// builds the stack was [Home, Other, Other], so back showed Other again.
// Should: the stack, the screen and the url stay as they were, and the code
// that opened Other still waits for its result. A navigation that is refused
// changes nothing: on the web, a navigation the navigate event cancels leaves
// the url and the current entry as they were, and Flutter's Navigator takes a
// new list of pages as one update, with no two pages of one key.
// On the web a link is one route unless the app asks for prefix matches, and
// goBack goes back in the browser's own history, which the headless test
// browser doesn't drive; those runs are skipped.
void main() {
  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  NamedRouteDef plainRoute(
    String name,
    String path, {
    List<AutoRouteGuard> guards = const [],
  }) => .new(
    name: name,
    path: path,
    guards: guards,
    builder: (_, _) => page(name),
  );

  RootStackRouter buildRouter() => .build(
    routes: [
      plainRoute('HomeRoute', '/'),
      plainRoute('OtherRoute', '/other'),
      plainRoute(
        'SecretRoute',
        '/secret',
        guards: [
          AutoRouteGuard.simple((resolver, _) => resolver.reject(goBack: true)),
        ],
      ),
    ],
  );

  for (final link in ['/secret?x=1', '/secret#top']) {
    testWidgets(
      'A link $link its guard rejects with goBack leaves the stack as it was',
      (tester) async {
        final router = buildRouter();
        await pumpRouterConfigApp(tester, router.config());
        var result = 'waiting';
        unawaited(
          router
              .push<int>(const NamedRoute('OtherRoute'))
              .then((value) => result = 'got ${value ?? 'null'}'),
        );
        await tester.pumpAndSettle();

        await tester.binding.handlePushRoute(link);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'OtherRoute',
        ]);
        expectTopPage(router, 'OtherRoute');
        expect(router.currentUrl, '/other');
        expect(result, 'waiting');

        unawaited(router.maybePop(7));
        await tester.pumpAndSettle();

        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        expectTopPage(router, 'HomeRoute');
        expect(result, 'got 7');
      },
      skip: kIsWeb,
    );
  }
}
