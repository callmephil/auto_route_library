import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../named_page.dart';
import '../router_test_utils.dart';

// Open the app at /protected, whose guard rejects it: no page is in, and the
// url the Router reports for the app is '/', not the rejected link. A browser
// can't cancel a load the app has received, so it must show what the app
// shows; Flutter's Router reports whatever currentConfiguration returns, and
// nothing while it is null. On the web it is always null: the web history
// writes the browser itself, from the router's urlState.
// With the pages a link brings below its own, a page let in below the
// rejected one shows, and the url is that page's.
// Web counterpart: example.old/integration_test/rejected_initial_link_url_test.dart
void main() {
  testWidgets('The url does not keep a link a guard rejected', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const NamedPage('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'ProtectedRoute',
          path: '/protected',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
          builder: (_, _) => const NamedPage('ProtectedRoute'),
        ),
      ],
    );
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    dispatcher.defaultRouteNameTestValue = '/protected';
    final config = router.config(includePrefixMatches: false);
    await pumpRouterConfigApp(tester, config);
    expect(router.stack.map((page) => page.name), ['HomeRoute']);
    final reported = kIsWeb
        ? router.urlState
        : config.routerDelegate.currentConfiguration;
    expect(reported?.uri.path, '/');
  });

  // Open the app at /secret/details, whose guard rejects it, with the pages a
  // link brings below its own, as off the web: Home is let in below it and
  // shows. The url the router reports was still the rejected link's, in its
  // url state, in what it reported to the Router and in the route
  // information provider.
  // Should: '/', the url of Home, the page on screen.
  testWidgets('The url names the page let in below a link a guard rejected', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const NamedPage('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'SecretRoute',
          path: '/secret/details',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
          builder: (_, _) => const NamedPage('SecretRoute'),
        ),
      ],
    );
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    dispatcher.defaultRouteNameTestValue = '/secret/details';
    final config = router.config(includePrefixMatches: true);
    await pumpRouterConfigApp(tester, config);

    expect(router.stack.map((page) => page.name), ['HomeRoute']);
    expect(router.urlState.url, '/');
    if (!kIsWeb) {
      expect(config.routerDelegate.currentConfiguration?.uri.path, '/');
      expect(config.routeInformationProvider?.value.uri.path, '/');
    }
  });
}
