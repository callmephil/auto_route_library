import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Found by an audit of auto_route/lib; no upstream issue. The same outcome as
// #1668, which was fixed for a slow guard
// (guards/link_during_initial_guard_test.dart), here through a slow
// deepLinkBuilder.
// AutoRouterDelegate awaited deepLinkBuilder and then opened what it
// returned, without checking whether a later link had started opening in the
// meantime. So when the builder took longer for an earlier link than for a
// later one, the earlier link's page opened last and ended on top. On a cold
// start from a link, iOS first hands the app '/' and then the link: with a
// builder that waits on the launch route alone, such as for a session to
// load, '/' landed after the link and took its page off again. An overtaken
// link is now dropped, unless the app shows no page yet. The links are
// numbered as they are handed over, before the builder is asked: a link
// gives up only when one handed over after it has started opening, so a
// builder that waits on every link opens them in the order they came.
//
// Native behavior this holds to: natively the link opened last is the one on
// screen, on iOS and Android alike; in Flutter's own Router the latest route
// wins, as a route information whose parse finishes after a newer one was
// reported is dropped (_RouterState._processParsedRouteInformation in
// widgets/router.dart: `if (_currentRouterTransaction != transaction)
// return;`).

// Hands [location] to the running app the way the engine does when the
// platform opens a link, without settling, so a test can pump on its own.
Future<void> sendPlatformLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    null,
  );
}

RootStackRouter _router({List<AutoRouteGuard> infoGuards = const []}) => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('InfoRoute', '/info'),
      ('OtherRoute', '/other'),
    ])
      NamedRouteDef(
        name: name,
        path: path,
        guards: name == 'InfoRoute' ? infoGuards : const [],
        builder: (_, _) => Text(name),
      ),
  ],
);

void main() {
  // Steps: the deepLinkBuilder waits one second on the launch route only; the
  // app starts at '/', and 50 ms later the platform hands it '/info'.
  // Should: InfoRoute is on screen once both have landed.
  testWidgets('A link handed over while the launch route waits on the '
      'deepLinkBuilder stays on screen', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: (link) async {
            if (link.initial) {
              await Future<void>.delayed(const Duration(seconds: 1));
            }
            return link;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await sendPlatformLink(tester, '/info');
    await tester.pump(const Duration(milliseconds: 50));
    expectCurrentPage(router, 'InfoRoute');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expectCurrentPage(router, 'InfoRoute');
  });

  // Steps: the deepLinkBuilder waits one second on '/other' only; the running
  // app is handed '/other' and, 50 ms later, '/info'.
  // Should: InfoRoute, the link handed over last, is on screen.
  testWidgets('Of two links to a running app, the one handed over last ends '
      'on screen', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(
        includePrefixMatches: false,
        deepLinkBuilder: (link) async {
          if (link.path == '/other') {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          return link;
        },
      ),
    );
    await sendPlatformLink(tester, '/other');
    await tester.pump(const Duration(milliseconds: 50));
    await sendPlatformLink(tester, '/info');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expectCurrentPage(router, 'InfoRoute');
  });

  // Steps: the deepLinkBuilder waits one second on the launch route; 50 ms
  // after the app starts at '/', the platform hands it '/info', whose guard
  // rejects it.
  // Should: the launch route still opens, since the app shows no page yet.
  testWidgets('A launch route a rejected link overtook still opens', (
    tester,
  ) async {
    final router = _router(
      infoGuards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: (link) async {
            if (link.initial) {
              await Future<void>.delayed(const Duration(seconds: 1));
            }
            return link;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await sendPlatformLink(tester, '/info');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expectCurrentPage(router, 'HomeRoute');
  });

  // Steps: the deepLinkBuilder waits one second on every link the running
  // app is handed, as one that looks something up does; the app is handed
  // '/other' and, 50 ms later, '/info'.
  // Should: InfoRoute, the link handed over last, is on screen, with its url.
  testWidgets('Of two links a builder answers in the order they came, the '
      'one handed over last ends on screen', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(
        includePrefixMatches: false,
        deepLinkBuilder: (link) async {
          if (!link.initial) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          return link;
        },
      ),
    );
    await sendPlatformLink(tester, '/other');
    await tester.pump(const Duration(milliseconds: 50));
    await sendPlatformLink(tester, '/info');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expectCurrentPage(router, 'InfoRoute');
    expect(router.currentUrl, '/info');
  });

  // Steps: the deepLinkBuilder waits for the session on every link; the app
  // starts at '/', 50 ms later the platform hands it '/info', and then the
  // session loads.
  // Should: InfoRoute, the link handed over after the launch route, is on
  // screen.
  testWidgets('On a cold start with a builder that waits on every link, the '
      'link handed over after the launch route ends on screen', (tester) async {
    final session = Completer<void>();
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: (link) async {
            await session.future;
            return link;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await sendPlatformLink(tester, '/info');
    await tester.pump(const Duration(milliseconds: 50));
    session.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expectCurrentPage(router, 'InfoRoute');
    expect(router.currentUrl, '/info');
  });

  // Steps: the deepLinkBuilder of the running app waits for one shared
  // refresh on every link; the app is handed '/other' and '/info', and then
  // the refresh ends, so the builder answers both in one go.
  // Should: InfoRoute, the link handed over last, is on screen.
  testWidgets('Of two links a builder answers at the same time, the one '
      'handed over last ends on screen', (tester) async {
    final refresh = Completer<void>();
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(
        includePrefixMatches: false,
        deepLinkBuilder: (link) async {
          if (!link.initial) await refresh.future;
          return link;
        },
      ),
    );
    await sendPlatformLink(tester, '/other');
    await tester.pump(const Duration(milliseconds: 50));
    await sendPlatformLink(tester, '/info');
    await tester.pump(const Duration(milliseconds: 50));
    refresh.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expectCurrentPage(router, 'InfoRoute');
    expect(router.currentUrl, '/info');
  });
}
