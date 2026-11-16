// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// On the web the navigation history alone writes the browser's entries, and
// Flutter's Router writes none. The Router used to write the url once a
// frame, after it, whatever the history had written or stepped meanwhile.
// The two could then leave an entry of a closed page, or one entry too
// many, depending on when the frame came.
//
// A Router reports nothing while the currentConfiguration of its delegate
// is null, which is how Flutter has a delegate say that it reports no
// route. AutoRouterDelegate.currentConfiguration is null on the web. A
// route the Router reports by itself has the type none, while the history
// writes each entry as a navigation or, for a replace, as neglected.
//
// Native behavior this holds to, the HTML History API. Each pushState and
// replaceState has one caller, and they run in the order they are called.

// Passes everything on to [_inner] and keeps the type of each write.
class _RecordingProvider extends RouteInformationProvider {
  new(this._inner);

  final RouteInformationProvider _inner;

  final types = <RouteInformationReportingType>[];

  @override
  RouteInformation get value => _inner.value;

  @override
  void addListener(VoidCallback listener) => _inner.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _inner.removeListener(listener);

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = .none,
  }) {
    types.add(type);
    _inner.routerReportsNewRouteInformation(routeInformation, type: type);
  }
}

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: push A, push B, pop, then press the browser's back button, a
  // frame apart, with a provider that keeps the type of every write.
  for (final (label, provider)
      in <(String, (RouteInformationProvider, VoidCallback) Function())>[
        (
          "auto_route's own provider",
          () {
            final own = AutoRouteInformationProvider();
            return (own, own.dispose);
          },
        ),
        (
          "Flutter's provider",
          () {
            final platform = PlatformRouteInformationProvider(
              initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
            );
            return (platform, platform.dispose);
          },
        ),
      ]) {
    testWidgets('On web, with $label, the Router writes nothing and the '
        'history writes every entry', (tester) async {
      final router = _router();
      final delegate = router.delegate();
      addTearDown(delegate.dispose);
      final (written, dispose) = provider();
      addTearDown(dispose);
      final recording = _RecordingProvider(written);
      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: router.defaultRouteParser(),
          routeInformationProvider: recording,
        ),
      );
      await settleBrowser(tester);
      final first = browserSerialCount;

      unawaited(router.push(const NamedRoute('ARoute')));
      await settleBrowser(tester);
      unawaited(router.push(const NamedRoute('BRoute')));
      await settleBrowser(tester);
      expect((browserSerialCount - first, browserPath), (2, '/b'));
      router.pop();
      await settleBrowser(tester);
      expect((browserSerialCount - first, browserPath), (1, '/a'));
      await pressBrowserBack(tester);
      expect((browserSerialCount - first, browserPath), (0, '/'));
      expect(router.stack.map((page) => page.name), ['HomeRoute']);

      expect(delegate.currentConfiguration, isNull);
      // The entry the app starts on, written over, then A and B.
      expect(recording.types, [
        RouteInformationReportingType.neglect,
        RouteInformationReportingType.navigate,
        RouteInformationReportingType.navigate,
      ]);
    });
  }
}
