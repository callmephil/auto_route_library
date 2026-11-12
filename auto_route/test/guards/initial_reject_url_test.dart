import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import '../named_page.dart';
import '../router_test_utils.dart';

// Open the app at /protected, whose guard rejects it: no page is in, and the
// url the Router reports for the app is '/', not the rejected link. A browser
// can't cancel a load the app has received, so it must show what the app
// shows; Flutter's Router reports whatever currentConfiguration returns, and
// nothing while it is null.
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
    expect(router.stack, isEmpty);
    expect(config.routerDelegate.currentConfiguration?.uri.path, '/');
  });
}
