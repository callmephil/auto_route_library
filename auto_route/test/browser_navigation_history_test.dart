import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_sequences.dart';
import 'history_test_browser.dart';
import 'router_test_utils.dart';

// The web history, BrowserNavigationHistory, with a real router and a
// browser whose landings the test releases, on the VM: what the browser
// holds after calls on the router, however fast they follow each other and
// whenever the browser lands, and what its back and forward buttons then
// show.
//
// Native behavior this holds to: Flutter's Navigator under Android's system
// back and the iOS back gesture, which reach the app as
// RouterDelegate.popRoute. Back closes the page on top, and a page the app
// closed never comes back. The forward button and the entries ahead follow
// the HTML History API. The same walk runs in Chrome in
// test/web/native_walk_web_test.dart.

// The app of a test: its router and the browser it writes.
class _App {
  new(this.tester, {bool isGuarded = false}) {
    router = HistoryRouter(
      isGuarded: isGuarded,
      // The test's clock runs through every animation at once; the browser
      // of a test lands late, never too late.
      history: (stack) => BrowserNavigationHistory(
        stack,
        browser,
        landingLimit: const Duration(hours: 1),
      ),
    );
    // The engine reports each entry the browser lands on to the Router.
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final HistoryRouter router;
  late final RouterConfig<UrlState> config = router.config();

  Future<void> start(List<String> opens) async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(tester, config);
    await settle();
    for (final name in opens) {
      unawaited(router.push(NamedRoute(name)));
      await settle();
    }
  }

  // Runs frames and lands every step until the browser holds what the app
  // shows.
  Future<void> settle() => browser.settle(tester);

  // Makes [calls], [gap] apart. With [landsLate] the browser lands no step
  // before the last call is made.
  Future<void> make(
    List<HistoryCall> calls,
    CallGap gap, {
    bool landsLate = false,
  }) async {
    for (final (index, call) in calls.indexed) {
      call(router);
      if (index == calls.length - 1) break;
      switch (gap) {
        case .frame:
          await (landsLate ? tester.pumpAndSettle() : settle());
        case .none:
          break;
        case .microtasks:
          for (var i = 0; i < 30; i++) {
            await Future<void>.value();
          }
      }
    }
    await settle();
  }

  // The urls of the entries on the way back, the app's first entry first.
  List<String> get wayBack => [
    for (final (url, _) in browser.entries.take(browser.index + 1)) url,
  ];

  // The page on top and the url the browser shows.
  String get shown => '${router.topRoute.name} ${browser.url}';

  // The page on top and its url after each system back, until it closes
  // nothing more.
  Future<List<String>> systemBackWalk() async {
    final walk = ['${router.topRoute.name} ${_url(router.urlState.url)}'];
    while (await config.routerDelegate.popRoute()) {
      await settle();
      walk.add('${router.topRoute.name} ${_url(router.urlState.url)}');
    }
    return walk;
  }

  // The page on top and the browser's url after each press of its back
  // button, down to the app's first entry.
  Future<List<String>> backButtonWalk() async {
    final walk = [shown];
    while (browser.didPressBack()) {
      await settle();
      walk.add(shown);
    }
    return walk;
  }

  // The same for [presses] of the forward button.
  Future<List<String>> forwardButtonWalk(int presses) async {
    final walk = <String>[];
    for (var i = 0; i < presses && browser.didPressForward(); i++) {
      await settle();
      walk.add(shown);
    }
    return walk;
  }
}

String _url(String url) => url.isEmpty ? '/' : url;

// The ways a sequence is run: how far apart its calls are, and whether the
// browser lands its steps only after the last call.
const List<(String, CallGap, bool)> _timings = [
  ('a frame apart', CallGap.frame, false),
  ('a frame apart, the browser landing late', CallGap.frame, true),
  ('in one turn', CallGap.none, true),
  ('microtasks apart', CallGap.microtasks, true),
];

void main() {
  // Every entry the browser held after each sequence a frame apart, the
  // ones ahead included, for the other timings to end on.
  final heldApart = <String, String>{};

  for (final (source, rows) in [
    ('as Chrome held them a frame apart', recordedSequences),
    ('once worse than a frame apart', onceWorseSequences),
    ('as the Navigator holds them', nativeSequences),
  ]) {
    group('The browser holds the entries $source:', () {
      for (final MapEntry(key: name, value: (opens, calls, entries))
          in rows.entries) {
        for (final (label, gap, landsLate) in _timings) {
          testWidgets('$name, $label', (tester) async {
            final app = _App(tester);
            await app.start(opens);
            await app.make(calls, gap, landsLate: landsLate);
            expect(app.wayBack, entries);
            expect(app.browser.held, heldApart[name] ??= app.browser.held);
          });
        }
      }
    });
  }

  // Steps: open A, B and C over Home, call popUntilRoot, then press the
  // forward button three times.
  // Was, while the writer brought the browser to each page popUntil closes,
  // in the order it closes them, the pages in between first: only C stayed
  // ahead.
  testWidgets('popUntilRoot steps the browser back once and leaves every '
      'page it closed ahead', (tester) async {
    final app = _App(tester);
    await app.start(['ARoute', 'BRoute', 'CRoute']);
    app.browser.asked.clear();
    app.router.popUntilRoot();
    await app.settle();
    expect(app.browser.asked, ['go -3']);
    expect(app.browser.held, '>/ /a /b /c');
    expect(await app.forwardButtonWalk(3), [
      'ARoute /a',
      'BRoute /b',
      'CRoute /c',
    ]);
  });

  // Steps: open A, B and C over Home and call popUntilRoot; before the
  // browser has landed, the Router hands the delegate '/c' again, the url
  // its provider holds, as it does when a dependency of its own changes.
  // Was: with the Router silent, that url was followed as a link, and C
  // opened again.
  testWidgets('The url the browser stands on, handed over again with no '
      'landing, is not followed', (tester) async {
    final app = _App(tester);
    await app.start(['ARoute', 'BRoute', 'CRoute']);
    app.router.popUntilRoot();
    await tester.pumpAndSettle();
    expect(app.browser.isStepping, isTrue);
    app.browser.onLanded?.call();
    await app.settle();
    expect(app.router.stack.map((page) => page.name), ['HomeRoute']);
    expect(app.browser.held, '>/ /a /b /c');
  });

  // Steps: open A, B and C over Home and call popUntilRoot; then the user
  // goes three entries forward at once, onto the entry of C.
  // Native behavior this holds to: the HTML History API, where history.go(3)
  // lands on the third entry ahead and passes the two between. The app
  // shows that entry's page as it shows a link, so C is over Home and takes
  // the entry over Home's: the back button then shows Home.
  testWidgets('A jump forward over several entries opens the page of the '
      'entry landed on, on the entry over the page under it', (tester) async {
    final app = _App(tester);
    await app.start(['ARoute', 'BRoute', 'CRoute']);
    app.router.popUntilRoot();
    await app.settle();
    expect(app.browser.held, '>/ /a /b /c');

    expect(app.browser.didJump(3), isTrue);
    await app.settle();
    expect(app.router.stack.map((page) => page.name), ['HomeRoute', 'CRoute']);
    expect(app.browser.held, '/ >/c');
    expect(await app.backButtonWalk(), ['CRoute /c', 'HomeRoute /']);
  });

  // Steps: over Home, push a page whose url is kept out of the address bar
  // and then B. Press the back button.
  // Was, while the web history was being built: the back button showed the
  // page kept out, on the entry of Home.
  // Native behavior this holds to: the HTML History API, where the back
  // button goes to the entry before. A page kept out of the address bar
  // has none, which the README section on keeping a url out of the address
  // bar tells of.
  for (final (label, gap, landsLate) in _timings) {
    testWidgets('The back button skips a page kept out of the address bar, '
        '$label', (tester) async {
      final app = _App(tester);
      await app.start([]);
      await app.make(
        [
          (router) => unawaited(router.push(const NamedRoute('KeptRoute'))),
          (router) => unawaited(router.push(const NamedRoute('BRoute'))),
        ],
        gap,
        landsLate: landsLate,
      );
      expect(app.browser.held, '/ >/b');
      expect(app.browser.didPressBack(), isTrue);
      await app.settle();
      expect(app.router.stack.map((page) => page.name), ['HomeRoute']);
      expect(app.browser.held, '>/ /b');
    });
  }

  group('The browser holds the entries where the router reports a '
      'replace:', () {
    for (final MapEntry(key: name, value: (opens, calls, entries))
        in replaceSequences.entries) {
      testWidgets(name, (tester) async {
        final app = _App(tester);
        await app.start(opens);
        await app.make(calls, .frame);
        expect(app.wayBack, entries);
      });
    }
  });

  // Steps: make the calls on two routers; on one walk back with the system
  // back, on the other with the browser's back button, then its forward
  // button.
  group("The browser's back button shows the pages the system back "
      'shows:', () {
    for (final MapEntry(key: name, value: (opens, calls, _)) in {
      ...recordedSequences,
      ...onceWorseSequences,
      ...nativeSequences,
    }.entries) {
      // A tab the user changed to has an entry of its own, and
      // pushPathState adds one: the browser's, with no page to close.
      if (name.contains('Tabs') || name.contains('pushPathState')) continue;
      for (final (label, gap, landsLate) in _timings) {
        testWidgets('$name, $label', (tester) async {
          final native = _App(tester);
          await native.start(opens);
          await native.make(calls, .frame);
          final systemBack = await native.systemBackWalk();
          await tester.pumpWidget(const SizedBox());

          final app = _App(tester);
          await app.start(opens);
          await app.make(calls, gap, landsLate: landsLate);
          final back = await app.backButtonWalk();
          expect(back, systemBack);
          expect(
            await app.forwardButtonWalk(back.length - 1),
            systemBack.reversed.skip(1),
          );
        });
      }
    }
  });
}
