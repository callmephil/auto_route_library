import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Off the web, back() in an AutoRouter.declarative steps back through every
// page the app's list showed.
// Headless test: auto_route/test/back_in_declarative_router_test.dart.
//
// Native behavior this holds to: a declarative Navigator's pages are the
// app's list, rebuilt by the app after it is told (Navigator.onDidRemovePage,
// navigator.dart 1662-1675, Flutter 3.50.0), and pop takes the top-most
// route only (navigator.dart 5607). Off the web only: on the web, back() is
// the browser's own back step.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back() in a declarative router, off the web', () {
    // Steps: Home, then A, then Decl, whose declarative router lists X; the
    // app's list grows to X, Y, Z; back() until the history can't.
    // Was: back() showed Y, then stayed on Y however often it was called.
    // Should: Z, Y, X, A, Home.
    testWidgets(
      'back() walks every page the list showed',
      (tester) async {
        final listed = ValueNotifier(['XRoute']);
        addTearDown(listed.dispose);
        final router = _router(listed);
        await pumpRouterAppWithConfig(tester, router);
        for (final page in ['ARoute', 'DeclRoute']) {
          unawaited(router.push(NamedRoute(page)));
          await tester.pumpAndSettle();
        }
        listed.value = ['XRoute', 'YRoute', 'ZRoute'];
        await tester.pumpAndSettle();

        final walk = [router.currentUrl];
        for (
          var i = 0;
          i < 8 && router.navigationHistory.canNavigateBack;
          i++
        ) {
          router.back();
          await tester.pumpAndSettle();
          walk.add(router.currentUrl);
        }
        expect(walk, ['/decl/z', '/decl/y', '/decl', '/a', '/']);
        expectTopPage(router, 'HomeRoute');
      },
      skip: kIsWeb,
    );
  });
}

RootStackRouter _router(ValueNotifier<List<String>> listed) => .build(
  routes: [
    for (final (name, path) in [('HomeRoute', '/'), ('ARoute', '/a')])
      NamedRouteDef(
        name: name,
        path: path,
        builder: (_, _) => Scaffold(body: Text(name)),
      ),
    NamedRouteDef(
      name: 'DeclRoute',
      path: '/decl',
      builder: (_, _) => ValueListenableBuilder<List<String>>(
        valueListenable: listed,
        builder: (_, pages, _) => AutoRouter.declarative(
          routes: (_) => [for (final page in pages) NamedRoute(page)],
          // The app goes back to the last page it is told.
          onNavigate: (routes) {
            final at = listed.value.indexOf(routes.lastOrNull?.name ?? '');
            if (at != -1) listed.value = listed.value.sublist(0, at + 1);
          },
          onPopRoute: (route, _) => listed.value = [
            for (final page in listed.value)
              if (page != route.name) page,
          ],
        ),
      ),
      children: [
        for (final (name, path) in [
          ('XRoute', ''),
          ('YRoute', 'y'),
          ('ZRoute', 'z'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) => Scaffold(body: Text(name)),
          ),
      ],
    ),
  ],
);
