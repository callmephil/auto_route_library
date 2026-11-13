// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, router.pushPathState always adds a browser entry, as
// history.pushState does: also right after a navigation that replaced the
// browser entry, such as router.replace, and with null as the state. It used
// to build its url state with `urlState.copyWith(pathState: state)`, which
// kept shouldReplace from the last navigation, so after a replace it wrote
// the state over the current entry and the browser's back button skipped the
// page as it was before the state; and copyWith can't set a field to null, so
// after pushPathState('x'), pushPathState(null) changed nothing.
//
// Native behavior this holds to: the HTML History API. history.pushState
// always adds an entry, also right after a replaceState, and takes null as a
// state like any other. The doc comment of NavigationHistory.pushPathState
// says it "Pushes a new browser entry with given state".
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('SecondRoute', '/second'),
      ('ThirdRoute', '/third'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
  ],
);

// The Chrome runner doesn't print a failed expectation, so each step says
// where the browser and the router are when the test fails.
void _note(String step, RootStackRouter router) => printOnFailure(
  '$step: browser at $browserPath, entry $browserSerialCount; '
  'router.pathState ${router.pathState ?? 'none'}',
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Control: after a push, pushPathState adds an entry.
  testWidgets('On web, pushPathState after a push adds a browser entry', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('SecondRoute')));
    await settleBrowser(tester);
    final before = browserSerialCount;

    router.pushPathState('y');
    await settleBrowser(tester);
    expect(router.pathState, 'y');
    expect((browserPath, browserSerialCount), ('/second', before + 1));
  });

  // Steps: push Second, replace it with Third, then call pushPathState('y').
  testWidgets('On web, pushPathState after a replace adds a browser entry', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('SecondRoute')));
    await settleBrowser(tester);
    unawaited(router.replace(const NamedRoute('ThirdRoute')));
    await settleBrowser(tester);
    final before = browserSerialCount;
    _note('after replace', router);
    expect(browserPath, '/third');

    router.pushPathState('y');
    await settleBrowser(tester);
    _note("after pushPathState('y')", router);
    expect(router.pathState, 'y');
    expect((browserPath, browserSerialCount), ('/third', before + 1));
  });

  // Steps: push Second, call pushPathState('x'), then pushPathState(null).
  testWidgets('On web, pushPathState(null) adds an entry without a state', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('SecondRoute')));
    await settleBrowser(tester);
    router.pushPathState('x');
    await settleBrowser(tester);
    final before = browserSerialCount;
    _note("after pushPathState('x')", router);

    router.pushPathState(null);
    await settleBrowser(tester);
    _note('after pushPathState(null)', router);
    expect(router.pathState, isNull);
    expect((browserPath, browserSerialCount), ('/second', before + 1));
  });
}
