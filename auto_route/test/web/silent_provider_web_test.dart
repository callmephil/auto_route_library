// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import 'browser_history.dart';

// On the web, an app whose route information provider writes no browser
// entry, as one that keeps its pages out of the browser's history, never
// moves the browser through its history: the entries there are other
// pages', and a step would leave the app.
//
// Before the web history became the browser's one writer, a pop stepped the
// browser back, for an entry the app had never written.
//
// Native behavior this holds to: the HTML History API, where history.go
// moves through the entries of the tab whoever wrote them, so a page that
// wrote none has none of its own to step through.

// Tells the app's first route, and writes nothing: it keeps
// routerReportsNewRouteInformation as RouteInformationProvider has it.
class _SilentProvider extends RouteInformationProvider with ChangeNotifier {
  @override
  RouteInformation get value => .new(uri: Uri.parse('/'));
}

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: another page's entry is ahead of the app's; then push A, push B
  // and pop a frame apart, push C and pop it in one turn, and popUntilRoot.
  testWidgets('On web, with a provider that writes no browser entry, the '
      "app's navigations leave the browser where it stands", (tester) async {
    // An entry ahead, as a page the user came back from leaves one.
    window.history.pushState(null, '', '#/elsewhere');
    await browserMove(tester, () => window.history.back());
    final router = _router();
    final delegate = router.delegate();
    addTearDown(delegate.dispose);
    final provider = _SilentProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: router.defaultRouteParser(),
        routeInformationProvider: provider,
      ),
    );
    await settleBrowser(tester);
    final start = (browserSerialCount, browserPath);
    var landings = 0;
    final moves = window.onPopState.listen((_) => landings++);
    addTearDown(moves.cancel);

    for (final call in <void Function()>[
      () => unawaited(router.push(const NamedRoute('ARoute'))),
      () => unawaited(router.push(const NamedRoute('BRoute'))),
      router.pop,
      () {
        unawaited(router.push(const NamedRoute('CRoute')));
        router.pop();
      },
      router.popUntilRoot,
    ]) {
      call();
      await settleBrowser(tester);
      // Long enough for a step to land.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }

    expect(router.stack.map((page) => page.name), ['HomeRoute']);
    expect(((browserSerialCount, browserPath), landings), (start, 0));
  });
}
