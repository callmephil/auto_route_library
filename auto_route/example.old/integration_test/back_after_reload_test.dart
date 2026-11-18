import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On web, after a reload, the back and forward buttons onto the entries from
// before the reload show the page of each entry alone, and never pile pages
// over the ones open.
// Headless test: auto_route/test/web/reload_back_web_test.dart
//
// The reload is made the way the headless test makes it: the app is taken
// down and a new one starts on the same browser history. A real reload under
// flutter drive would restart the page that runs the tests, and the driver
// would lose the run.
//
// Native behavior this holds to: the HTML standard's session history
// traversal and the History API, as a real Chrome shows for a reloaded page
// that moves with history.pushState: the back button lands on one entry and
// fires a single popstate with that entry's url and state, and the page shows
// that entry; the entries ahead stay for the forward button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after reload', () {
    // Steps: Home, push Shoes, push Runner X, reload on Runner X, then the
    // browser's back twice and forward twice.
    // Should: back shows Shoes alone, then Home alone; forward shows Shoes
    // over Home, then Runner X over them; the address bar names each page.
    testWidgets(
      'back and forward after a reload show the page of each entry from '
      'before it, alone',
      skip: !kIsWeb,
      (tester) async {
        // The app before the reload, and the app after it.
        final [first, router] = [for (var i = 0; i < 2; i++) _router()];
        await pumpRouterConfigApp(tester, first.config());
        for (final name in ['ShoesRoute', 'RunnerXRoute']) {
          await expectBrowserEntryAfter(
            1,
            () => unawaited(first.push(NamedRoute(name))),
          );
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        first.dispose();

        // The reload. The route information provider reads the url the app
        // opens at when the config is made, so the url is set first.
        addTearDown(router.dispose);
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/runner-x';
        final config = router.config();
        await pumpAppAtDeepLink(
          tester,
          '/runner-x',
          MaterialApp.router(routerConfig: config),
        );
        expect(_names(router), ['RunnerXRoute']);

        for (final (move, url, stack) in [
          (pressBrowserBack, '/shoes', ['ShoesRoute']),
          (pressBrowserBack, '/', ['HomeRoute']),
          (pressBrowserForward, '/shoes', ['HomeRoute', 'ShoesRoute']),
          (
            pressBrowserForward,
            '/runner-x',
            ['HomeRoute', 'ShoesRoute', 'RunnerXRoute'],
          ),
        ]) {
          final change = identical(move, pressBrowserBack) ? -1 : 1;
          await expectBrowserEntryAfter(change, move);
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(_names(router), stack, reason: 'at $url');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}

List<String?> _names(StackRouter router) => [
  for (final page in router.stack) page.name,
];

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ShoesRoute', '/shoes'),
      ('RunnerXRoute', '/runner-x'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);
