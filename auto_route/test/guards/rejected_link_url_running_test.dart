import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// After a link a guard rejected, the running app's url was the rejected
// link's while the screen showed the page it was on: the delegate set the
// link's url before its guards ran, and a rejected single route changes no
// page, so nothing rebuilt the url. currentUrl, urlState and isPathActive
// were wrong the same way. The app now puts back the url of the pages it
// shows, as it does for a link rejected at launch.
// Steps: open Home, push Details (url /details). The platform hands the app
// the link /guarded, whose guard rejects it.
// Native behavior this holds to: on the web a canceled navigation leaves the
// url and the current entry as they were (HTML, the navigate event), and the
// address bar names what is on screen.
void main() {
  testWidgets('The url names the page on screen after a rejected link', (
    tester,
  ) async {
    final router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('DetailsRoute', '/details'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => Scaffold(body: Text(name)),
          ),
        NamedRouteDef(
          name: 'GuardedRoute',
          path: '/guarded',
          guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
          builder: (_, _) => const Scaffold(body: Text('GuardedRoute')),
        ),
      ],
    );
    final config = router.config();
    await pumpRouterConfigApp(tester, config);
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(router.isPathActive('/details'), isTrue);

    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.routeData.name), [
      'HomeRoute',
      'DetailsRoute',
    ]);
    expect(router.currentUrl, '/details');
    expect(config.routerDelegate.currentConfiguration?.uri.path, '/details');
    expect(router.isPathActive('/guarded'), isFalse);
  });
}
