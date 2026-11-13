// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, the browser's back button leaves an entry the app made with
// router.pushPathState: it lands on the entry before, whose state the router
// then reports, and the entry left stays ahead for the forward button. A page
// pushed after pushPathState goes back through the state the same way. Each
// press used to land on the entry before and have the app write the state
// again at once as a new entry, which also cut off the entries ahead. The
// example app's "Update State" counter
// (example.old/lib/web_demo/router/web_app_router.dart) does exactly this.
//
// Native behavior this holds to: the HTML History API. history.pushState adds
// an entry; back traverses to the entry before it, whose state the popstate
// event carries, and the entry left stays ahead for the forward button (HTML
// standard, "traverse the history by a delta", PopStateEvent.state). The doc
// comments of NavigationHistory say the same: pushPathState "Pushes a new
// browser entry with given state", and pathState "Reads the current browser
// entry state". Going back between two entries of one document asks no
// beforeunload handler, so a PopScope that refuses to be left isn't asked
// either: no page closes.
//
// [secondPage] wraps the page of Second, which shows its name.
RootStackRouter _router({Widget Function(Widget page) secondPage = _asItIs}) =>
    .build(
      routes: [
        for (final (name, path) in [
          ('HomeRoute', '/'),
          ('SecondRoute', '/second'),
          ('ThirdRoute', '/third'),
        ])
          NamedRouteDef(
            name: name,
            path: path,
            builder: (_, _) =>
                name == 'SecondRoute' ? secondPage(Text(name)) : Text(name),
          ),
      ],
    );

Widget _asItIs(Widget page) => page;

// The Chrome runner doesn't print a failed expectation, so each step says
// where the browser and the router are when the test fails.
void _note(String step, RootStackRouter router) => printOnFailure(
  '$step: browser at $browserPath, entry $browserSerialCount; '
  'router.pathState ${router.pathState ?? 'none'}, top page ${router.current.name}',
);

// Checks the browser's entry and url, and the state the router reports.
void _expectEntry(RootStackRouter router, int entry, Object? state) => expect(
  (browserPath, browserSerialCount, router.pathState),
  ('/second', entry, state),
);

// Presses the browser's back (-1) or forward (1) button and settles, giving
// up after two seconds when the browser has no entry to go to, so a failing
// test ends instead of waiting for its timeout.
Future<void> _step(WidgetTester tester, int delta) async {
  final landedOn = window.onPopState.first
      .then<int?>((_) => browserSerialCount)
      .timeout(const Duration(seconds: 2), onTimeout: () => null);
  window.history.go(delta);
  final entry = await landedOn;
  printOnFailure(
    entry == null
        ? 'history.go($delta): the browser had no entry to go to'
        : 'history.go($delta): the browser landed on entry $entry',
  );
  await settleBrowser(tester);
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: push Second, call pushPathState('x'), press the browser's back
  // button, then its forward button.
  testWidgets('On web, back leaves an entry made by pushPathState', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('SecondRoute')));
    await settleBrowser(tester);
    final second = browserSerialCount;
    _note('on Second', router);

    router.pushPathState('x');
    await settleBrowser(tester);
    _note("after pushPathState('x')", router);
    _expectEntry(router, second + 1, 'x');

    await _step(tester, -1);
    _note('after browser back', router);
    _expectEntry(router, second, null);
    expectCurrentPage(router, 'SecondRoute');

    await _step(tester, 1);
    _note('after browser forward', router);
    _expectEntry(router, second + 1, 'x');
  });

  // Steps: push Second, call pushPathState('x'), push Third, then press the
  // browser's back button twice.
  testWidgets('On web, back from a page pushed after pushPathState walks '
      'back through the state', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('SecondRoute')));
    await settleBrowser(tester);
    final second = browserSerialCount;
    _note('on Second', router);
    router.pushPathState('x');
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('ThirdRoute')));
    await settleBrowser(tester);
    _note('on Third', router);
    expect((browserPath, browserSerialCount), ('/third', second + 2));

    await _step(tester, -1);
    _note('after browser back', router);
    expectCurrentPage(router, 'SecondRoute');
    _expectEntry(router, second + 1, 'x');

    await _step(tester, -1);
    _note('after a second browser back', router);
    expectCurrentPage(router, 'SecondRoute');
    _expectEntry(router, second, null);
  });
  // Steps: push Second, whose PopScope refuses to be left, call
  // pushPathState('x'), then press the browser's back button.
  // Was: the PopScope was asked and the browser sent forward again, so the
  // entry with 'x' could not be left.
  testWidgets('On web, back leaves an entry made by pushPathState on a page '
      'whose PopScope refuses to be left', (tester) async {
    var popAttempts = 0;
    final router = _router(
      secondPage: (page) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) popAttempts++;
        },
        child: page,
      ),
    );
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('SecondRoute')));
    await settleBrowser(tester);
    final second = browserSerialCount;
    router.pushPathState('x');
    await settleBrowser(tester);
    _note("after pushPathState('x')", router);
    _expectEntry(router, second + 1, 'x');

    await _step(tester, -1);
    _note('after browser back', router);
    printOnFailure('the PopScope was asked $popAttempts times');
    expect(popAttempts, 0);
    _expectEntry(router, second, null);
    expectCurrentPage(router, 'SecondRoute');
  });
}
