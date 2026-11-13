import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the review of the batch's round 4 (Part 6, finding 1); new with
// the batch, not on dev.
// Once a later link had been let in, the app's own replaceAll, navigate,
// pushAll or navigatePath did nothing, and reported no failure, when the
// code that called it was set up while an earlier link opened: a listener or
// a timer a guard starts in its first call, also for the link the app was
// opened at. Every batch read its link from the zone the link's navigation
// ran in, and a zone outlives the link, so such a batch counted as the
// earlier link's and gave up once a later link was let in. A batch is now a
// link's only when the router starts it for that link: the link is handed
// down as an argument, and a navigation the app makes is never a link's.
// Steps: a guard of Account starts to listen for the end of the session in
// its first call. The platform hands the app /account, then /settings. The
// session ends, and the listener navigates to the login page.
// Native behavior this holds to: a navigation the app asks for runs as asked,
// whatever links came before it, as on Android and iOS an app's own
// navigation is not tied to the intent or URL that opened a screen.
void main() {
  late RootStackRouter router;
  late StreamController<String> signedOut;
  StreamSubscription<String>? listening;

  // Listens for the end of the session once, in its first call, as a guard
  // that sets itself up lazily does; the listener navigates as [how] says.
  AutoRouteGuard sessionGuard() => .simple((resolver, _) {
    listening ??= signedOut.stream.listen((how) {
      const login = NamedRoute('LoginRoute');
      unawaited(switch (how) {
        'replaceAll' => router.replaceAll([login]),
        'navigate' => router.navigate(login),
        'pushAll' => router.pushAll([login]),
        'push' => router.push(login),
        _ => router.navigatePath('/login'),
      });
    });
    resolver.next();
  });

  RootStackRouter build() {
    final guard = sessionGuard();
    return .build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('AccountRoute', '/account'),
          ('SettingsRoute', '/settings'),
          ('LoginRoute', '/login'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            guards: [if (name == 'AccountRoute') guard],
            builder: (_, _) => Scaffold(body: Center(child: Text(name))),
          ),
      ],
    );
  }

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  setUp(() {
    signedOut = StreamController<String>.broadcast(sync: true);
    listening = null;
  });
  tearDown(() async {
    await listening?.cancel();
    await signedOut.close();
  });

  for (final how in [
    'replaceAll',
    'navigate',
    'pushAll',
    'push',
    'navigatePath',
  ]) {
    testWidgets('$how from a listener a guard set up during a link opens the '
        'login page after a later link', (tester) async {
      router = build();
      await pumpRouterConfigApp(tester, router.config());

      await tester.binding.handlePushRoute('/account');
      await tester.pumpAndSettle();
      expect(stackNames().lastOrNull, 'AccountRoute');
      await tester.binding.handlePushRoute('/settings');
      await tester.pumpAndSettle();
      expect(stackNames().lastOrNull, 'SettingsRoute');

      signedOut.add(how);
      await tester.pumpAndSettle();

      expect(stackNames().lastOrNull, 'LoginRoute');
      expect(find.text('LoginRoute'), findsOneWidget);
      expect(router.currentUrl, '/login');
    });
  }

  testWidgets("replaceAll from a listener the guard of the app's start link "
      'set up replaces the pages after a later link', (tester) async {
    router = build();
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/account';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await pumpRouterConfigApp(tester, router.config());
    expect(stackNames().lastOrNull, 'AccountRoute');
    await tester.binding.handlePushRoute('/settings');
    await tester.pumpAndSettle();

    signedOut.add('replaceAll');
    await tester.pumpAndSettle();

    expect(stackNames(), ['LoginRoute']);
  });

  testWidgets('A timer a guard starts during a link navigates after a later '
      'link', (tester) async {
    router = RootStackRouter.build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('SettingsRoute', '/settings'),
          ('PlansRoute', '/plans'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => Scaffold(body: Text(name)),
          ),
        NamedRouteDef(
          name: 'TrialRoute',
          path: '/trial',
          guards: [
            AutoRouteGuard.simple((resolver, _) {
              // The trial ends later: the app then shows the plans.
              Timer(
                const Duration(seconds: 30),
                () =>
                    unawaited(router.navigate(const NamedRoute('PlansRoute'))),
              );
              resolver.next();
            }),
          ],
          builder: (_, _) => const Scaffold(body: Text('TrialRoute')),
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    await tester.binding.handlePushRoute('/trial');
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('/settings');
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(stackNames().lastOrNull, 'PlansRoute');
  });
}
