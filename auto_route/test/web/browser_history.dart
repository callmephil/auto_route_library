import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Router, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' show WindowEventGetters, window;

// Helpers for headless tests that run against the real browser history in
// Chrome.

/// Connects the test app to the browser's own history for the calling test
/// file.
///
/// Call it first in `main()` of a file marked `@TestOn('browser')`. By default,
/// widget tests on web run with the engine ignoring platform messages and
/// keeping history in memory, so routes never reach `window.history`; this
/// turns both off. The engine handles navigation messages one after another,
/// and on the default fake clock a message still waiting when a test ends
/// blocks every later one, so this also switches the file to
/// [LiveTestWidgetsFlutterBinding], which runs on the real clock.
void useRealBrowserHistory() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  ui_web.TestEnvironment.setUp(
    const ui_web.TestEnvironment(
      forceTestFonts: true,
      disableFontFallbacks: true,
      keepSemanticsDisabledOnUpdate: true,
    ),
  );
  ui_web.debugDefaultUrlStrategyOverride = const ui_web.HashUrlStrategy();
  // The test page's url carries the runner's metadata; start the app at '/'.
  window.history.replaceState(null, '', '#/');
}

/// Moves the browser back to its first entry, which holds '/', so a test starts there.
///
/// Call it from `setUp`. Entries after the first stay as forward entries until
/// the next navigation replaces them.
Future<void> rewindBrowserHistory() async {
  final stepsBack = browserSerialCount;
  if (stepsBack <= 0) return;
  final popped = window.onPopState.first;
  window.history.go(-stepsBack);
  await popped;
}

/// The serial number the engine gives the current browser history entry: 0
/// for the first entry the app wrote, -1 before the app wrote any.
int get browserSerialCount {
  final state = window.history.state.dartify();
  return state is Map ? (state['serialCount'] as num).toInt() : -1;
}

/// The number of entries of this page, from the Navigation API. Chrome stops
/// window.history.length at 50, so late in a long run it misses new entries.
int get browserEntryCount => globalContext
    .getProperty<JSObject>('navigation'.toJS)
    .callMethod<JSArray<JSObject>>('entries'.toJS)
    .toDart
    .length;

/// The app path the current browser history entry holds, such as '/second-route'.
String get browserPath => ui_web.urlStrategy!.getPath();

/// Pumps until the router settles and the browser holds what the app shows,
/// repeating while that schedules another frame.
///
/// The web history brings the browser to the app's pages by itself, entry by
/// entry, and waits for the browser to land after each step back; this waits
/// until it has nothing left to do, and fails after two seconds.
Future<void> settleBrowser(WidgetTester tester) async {
  do {
    await tester.pumpAndSettle();
    for (final history in _shownHistories(tester)) {
      await history.whenBrowserSettled().timeout(const Duration(seconds: 2));
    }
    // The engine handles navigation messages one after another, so its reply
    // to this one comes once every route reported before it is handled, the
    // report of a landing included.
    await SystemNavigator.selectMultiEntryHistory();
    await tester.pumpAndSettle();
  } while (tester.binding.hasScheduledFrame ||
      _shownHistories(tester).any((history) => !history.isBrowserSettled));
}

// The web histories of the routers the app shows.
Iterable<BrowserNavigationHistory> _shownHistories(WidgetTester tester) sync* {
  // MaterialApp builds a Router<Object>, whatever its delegate is.
  for (final router in tester.widgetList<Router<Object?>>(
    find.byWidgetPredicate((widget) => widget is Router<Object?>),
  )) {
    final delegate = router.routerDelegate;
    if (delegate is! AutoRouterDelegate) continue;
    final history = delegate.controller.navigationHistory;
    if (history is BrowserNavigationHistory) yield history;
  }
}

/// Runs [move], which moves the browser through its history, waits for the
/// browser's popstate event, and settles.
///
/// [move] is a back step from the app, such as `router.back`, or the browser's
/// own, such as `() => window.history.back()`, the call the back button makes.
///
/// Fails after five seconds when the browser has not landed: it had no entry
/// to move to.
Future<void> browserMove(WidgetTester tester, VoidCallback move) async {
  final popped = window.onPopState.first;
  move();
  await popped.timeout(const Duration(seconds: 5));
  await settleBrowser(tester);
}

/// Presses the browser's back button and settles.
///
/// Fails on the app's first entry, which every test starts on: the back
/// button would leave the app there, and the test's page with it.
Future<void> pressBrowserBack(WidgetTester tester) {
  if (browserSerialCount <= 0) {
    fail(
      "The browser stands on the app's first entry: its back button would "
      'leave the app.',
    );
  }
  return browserMove(tester, () => window.history.back());
}

/// Makes the browser's current entry hold [path], as when the app is opened at
/// a deep link, and makes [path] the app's initial route.
///
/// The entry keeps the engine's serial number, so [browserSerialCount] stays
/// where it was, and is marked as the browser's until the app writes it; see
/// [didAppWriteBrowserEntry]. Clears the initial route when the test ends.
void openBrowserAt(WidgetTester tester, String path) {
  final dispatcher = tester.binding.platformDispatcher;
  addTearDown(dispatcher.clearDefaultRouteNameTestValue);
  dispatcher.defaultRouteNameTestValue = path;
  final serialCount = browserSerialCount < 0 ? 0 : browserSerialCount;
  window.history.replaceState(
    {
      'serialCount': serialCount,
      'state': null,
      _kOpenedByBrowser: true,
    }.jsify(),
    '',
    '#$path',
  );
}

// Kept beside the engine's own keys: the app reads the engine's 'state' of
// the entry it starts at as the state it saved there.
const _kOpenedByBrowser = 'openedByBrowser';

/// Whether the app has written the browser's current entry since
/// [openBrowserAt] made it, as it does when it reports its route.
bool get didAppWriteBrowserEntry {
  final state = window.history.state.dartify();
  return !(state is Map && state[_kOpenedByBrowser] == true);
}

/// Shows [app] the way runApp starts an app, and settles.
///
/// runApp builds the widget tree before the first frame, and the frame comes
/// after the pending microtasks, so the Router reports the route of the
/// finished initial navigation. In a test the tree is already there, and
/// [WidgetTester.pumpWidget] builds the app inside a frame, so the Router
/// first reports the empty route of the unfinished navigation, as no app
/// started by runApp does.
Future<void> pumpAsRunApp(WidgetTester tester, Widget app) async {
  tester.binding.attachRootWidget(tester.binding.wrapWithDefaultView(app));
  tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
  await Future<void>.delayed(.zero);
  await settleBrowser(tester);
}

/// Presses the browser's forward button and settles.
Future<void> pressBrowserForward(WidgetTester tester) =>
    browserMove(tester, () => window.history.forward());

/// Runs a frame now, before the browser can make a move it was asked for in
/// this turn, such as the step back after a pop: only microtasks run between
/// the calls and this frame.
///
/// [settleBrowser] waits before each frame, so the browser's moves land first;
/// in an app the next frame may come first. Needs
/// [LiveTestWidgetsFlutterBindingFramePolicy.fullyLive], which a test sets with
/// [useLiveFrames].
Future<void> runFrameBeforeBrowserMoves(WidgetTester tester) async {
  final binding = tester.binding as LiveTestWidgetsFlutterBinding;
  // The end of the turn, where the history brings the browser in line.
  for (var i = 0; i < 4; i++) {
    await Future<void>.value();
  }
  binding
    ..handleBeginFrame(null)
    ..handleDrawFrame();
  // The engine takes the Router's report in microtasks.
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

/// Lets a test run frames itself, as [runFrameBeforeBrowserMoves] does, for
/// each test of the group or file it is called in.
void useLiveFrames() {
  LiveTestWidgetsFlutterBinding binding() =>
      TestWidgetsFlutterBinding.instance as LiveTestWidgetsFlutterBinding;
  setUp(() => binding().framePolicy = .fullyLive);
  tearDown(() => binding().framePolicy = .fadePointers);
}
