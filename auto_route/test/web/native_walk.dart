import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// The native walk: what the browser's back button shows after some calls on
// a router is measured against what the system back shows after the same
// calls, not against what the same code does at another speed.
//
// Native behavior this holds to: Flutter's Navigator, which Android's system
// back and the iOS back gesture drive through the Router's back button
// dispatcher and RouterDelegate.popRoute. Each back closes the page on top,
// and a page the app closed never comes back. The browser's forward button
// has no native twin; it follows the HTML History API, where forward returns
// to each entry that back left, in order.

/// A call on the router of a walk, such as a push or a pop.
typedef WalkCall = void Function(RootStackRouter router);

/// How long a walk waits between two of its calls.
enum WalkGap {
  /// A frame runs and the browser settles before the next call.
  frame,

  /// The calls follow each other in one turn.
  none,

  /// Only microtasks run between the calls, so the browser can't move.
  microtasks,

  /// 30 ms pass with no frame, so the browser's moves land between the calls.
  time,
}

/// A router with a Home page at '/', pages A to D at '/a' to '/d', and an
/// Item page whose url is '/item' whatever its args are.
RootStackRouter walkRouter() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
      ('ItemRoute', '/item'),
    ])
      NamedRouteDef(
        name: name,
        path: path,
        builder: (_, data) => Text('$name ${data.args ?? ''}'),
      ),
  ],
);

/// Runs [calls] on a router made by [router], with the pages named in [opens]
/// pushed over its first page a frame apart before them, and expects the
/// browser's back button to show, press by press, the pages that
/// [RouterDelegate.popRoute] shows on a second router after the same calls,
/// with the url of each in the address bar; then the forward button to reopen
/// them in reverse.
///
/// The calls of the browser's walk are [gap] apart. With [isFrameFirst] a
/// frame runs after them before the browser can move, which needs
/// `useLiveFrames`; otherwise the browser's moves land first. The calls of
/// the popRoute walk are always a frame apart; a test that runs the same
/// calls several ways passes the walk [systemBackWalk] gave it as
/// [systemBack].
Future<void> expectNativeWalk(
  WidgetTester tester, {
  required List<WalkCall> calls,
  List<String> opens = const [],
  RootStackRouter Function() router = walkRouter,
  WalkGap gap = .frame,
  bool isFrameFirst = false,
  List<String>? systemBack,
}) async {
  final native =
      systemBack ??
      await systemBackWalk(tester, calls: calls, opens: opens, router: router);

  final walked = router();
  await pumpRouterConfigApp(tester, walked.config());
  await settleBrowser(tester);
  final first = browserSerialCount;
  for (final name in opens) {
    unawaited(walked.push(NamedRoute(name)));
    await settleBrowser(tester);
  }
  for (final (index, call) in calls.indexed) {
    call(walked);
    if (index == calls.length - 1) break;
    switch (gap) {
      case .frame:
        if (isFrameFirst) await runFrameBeforeBrowserMoves(tester);
        await settleBrowser(tester);
      case .none:
        break;
      case .microtasks:
        for (var i = 0; i < 30; i++) {
          await Future<void>.value();
        }
      case .time:
        await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
  if (isFrameFirst) await runFrameBeforeBrowserMoves(tester);
  await _settleMoves(tester);

  final back = [_shownInBrowser(walked)];
  // A few presses more than the system back needed would show an entry too
  // many; the first entry is never left, since that would leave the test.
  for (var i = 0; i < native.length + 3 && browserSerialCount > first; i++) {
    await pressBrowserBack(tester);
    back.add(_shownInBrowser(walked));
  }
  // On the web a failed expectation's message is not shown with the test.
  printOnFailure(
    "The browser's back button showed $back; the system back "
    'shows $native.',
  );
  expect(
    back,
    native,
    reason:
        "the browser's back button, press by press, against the system "
        'back',
  );

  final forward = <String>[];
  for (var i = 1; i < back.length; i++) {
    if (!await _didPressForward(tester)) break;
    forward.add(_shownInBrowser(walked));
  }
  expect(
    forward,
    native.reversed.skip(1),
    reason: "the browser's forward button reopens what back closed",
  );
}

/// The page on top and its url after [calls], made a frame apart on a
/// router made by [router] with the pages named in [opens] over its first
/// page, then after each system back until it closes nothing more. Leaves
/// the browser on its first entry, with no app shown.
Future<List<String>> systemBackWalk(
  WidgetTester tester, {
  required List<WalkCall> calls,
  List<String> opens = const [],
  RootStackRouter Function() router = walkRouter,
}) async {
  final walked = router();
  final config = walked.config();
  await pumpRouterConfigApp(tester, config);
  await settleBrowser(tester);
  for (final name in opens) {
    unawaited(walked.push(NamedRoute(name)));
    await settleBrowser(tester);
  }
  for (final call in calls) {
    call(walked);
    await settleBrowser(tester);
  }
  final shown = [_shown(walked, walked.urlState.url)];
  while (await config.routerDelegate.popRoute()) {
    await settleBrowser(tester);
    shown.add(_shown(walked, walked.urlState.url));
  }
  await tester.pumpWidget(const SizedBox());
  await settleBrowser(tester);
  await rewindBrowserHistory();
  return shown;
}

String _shownInBrowser(RootStackRouter router) => _shown(router, browserPath);

// The page on top with [url], '/' for the empty url of the first page.
String _shown(RootStackRouter router, String url) =>
    '${router.topRoute.name} ${url.isEmpty ? '/' : url}';

// Settles, then gives the browser time for a move still on its way.
Future<void> _settleMoves(WidgetTester tester) async {
  await settleBrowser(tester);
  await tester.pump(const Duration(milliseconds: 200));
  await settleBrowser(tester);
}

// Presses the browser's forward button; false when no entry is ahead.
Future<bool> _didPressForward(WidgetTester tester) async {
  final moved = window.onPopState.first
      .then((_) => true)
      .timeout(const Duration(milliseconds: 400), onTimeout: () => false);
  window.history.forward();
  if (!await moved) return false;
  await settleBrowser(tester);
  return true;
}
