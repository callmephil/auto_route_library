// Runs only in Chrome, `flutter test --platform chrome`: it needs the web
// history. It has no testWidgets on purpose, since that sets up a binding.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// On the web, a router navigates before its widget is built and before any
// binding exists, as an app may set its first pages up in main before
// runApp. Since fb1e4ea8 the web history asked the scheduler binding for the
// frame's end on every navigation and threw "Binding has not yet been
// initialized". Only the Router writes the url, and there is none before the
// router is built, so the history keeps no account of a frame until then.
//
// Native behavior this holds to: Flutter's own RouterDelegate, its
// RouteInformationParser and Navigator pages are plain objects an app can
// make and change before runApp; only the Router widget, once built, reports
// a url to the engine.
void main() {
  test(
    'On web, a router navigates before runApp, with no binding yet',
    () async {
      final router = RootStackRouter.build(
        routes: [
          for (final (name, path) in [('HomeRoute', '/'), ('ARoute', '/a')])
            NamedRouteDef(
              name: name,
              path: path,
              builder: (_, _) => Text(name),
            ),
        ],
      );
      addTearDown(router.dispose);

      // Each push reports a url, which the web history keeps an account of
      // for the Router; an error it throws fails the test.
      unawaited(router.push(const NamedRoute('HomeRoute')));
      unawaited(router.push(const NamedRoute('ARoute')));
      await pumpEventQueue();
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ARoute']);
    },
  );
}
