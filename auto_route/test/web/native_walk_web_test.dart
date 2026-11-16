// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_history.dart';
import 'native_walk.dart';

// On the web, the browser's back button walks the pages the way the system
// back does on a phone: each press closes the page on top, and a page the app
// closed never comes back, however the page was closed and however fast the
// app navigated.
//
// Before the web history became the browser's one writer, the back button
// showed a closed page after calls that take a page off the stack without a
// pop, such as navigate to a page underneath, removeLast and replaceAll, a
// frame apart as in one turn: the page's entry stayed under the page on top.
// After several calls in one turn, or while the browser was still stepping
// back, it could show a closed page, skip a page or need a press too many.
//
// Native behavior this holds to: Flutter's Navigator under Android's system
// back and the iOS back gesture, which reach the app as
// RouterDelegate.popRoute; see native_walk.dart, which runs both walks and
// compares them.

WalkCall _push(String name, {Object? args}) =>
    (router) => unawaited(router.push(NamedRoute(name, args: args)));
WalkCall _replace(String name) =>
    (router) => unawaited(router.replace(NamedRoute(name)));
WalkCall _navigate(String name) =>
    (router) => unawaited(router.navigate(NamedRoute(name)));
void _pop(RootStackRouter router) => router.pop();
void _popUntilRoot(RootStackRouter router) => router.popUntilRoot();

const _abc = ['ARoute', 'BRoute', 'CRoute'];

// One call: the pages open before it, over Home, and the call.
final Map<String, (List<String>, WalkCall)> _calls = {
  'a push': (['ARoute'], _push('BRoute')),
  'a pop': (['ARoute', 'BRoute'], _pop),
  'a replace': (['ARoute', 'BRoute'], _replace('CRoute')),
  // The shape an app writes: each pop is a turn of its own, a few microtasks
  // after the one before.
  'two awaited maybePop calls': (
    _abc,
    (router) => unawaited(() async {
      await router.maybePop();
      await router.maybePop();
    }()),
  ),
  // The calls below take pages off the stack without a pop.
  'navigate to a page underneath': (_abc, _navigate('ARoute')),
  'removeLast': (_abc, (router) => router.removeLast()),
  'removeWhere of the page in between': (
    _abc,
    (router) => router.removeWhere((route) => route.name == 'BRoute'),
  ),
  'removeUntil': (
    _abc,
    (router) => router.removeUntil((route) => route.name == 'ARoute'),
  ),
  'replaceAll': (
    _abc,
    (router) => unawaited(router.replaceAll([const NamedRoute('DRoute')])),
  ),
  'pushAndPopUntil': (
    _abc,
    (router) => unawaited(
      router.pushAndPopUntil(
        const NamedRoute('DRoute'),
        predicate: (route) => route.settings.name == 'ARoute',
      ),
    ),
  ),
};

// Several calls: the pages open before them, over Home, and the calls.
final Map<String, (List<String>, List<WalkCall>)> _sequences = {
  'pop, pop': (_abc, [_pop, _pop]),
  'pop, pop, push C, push D, pop': (
    ['ARoute', 'BRoute'],
    [_pop, _pop, _push('CRoute'), _push('DRoute'), _pop],
  ),
  'popUntilRoot, push C, push D': (
    ['ARoute', 'BRoute'],
    [_popUntilRoot, _push('CRoute'), _push('DRoute')],
  ),
  'replace B, pop, push C': (
    ['ARoute'],
    [_replace('BRoute'), _pop, _push('CRoute')],
  ),
  'replace B, replace C, pop, push D': (
    ['ARoute'],
    [_replace('BRoute'), _replace('CRoute'), _pop, _push('DRoute')],
  ),
  'push B, navigate to A underneath, push C': (
    ['ARoute'],
    [_push('BRoute'), _navigate('ARoute'), _push('CRoute')],
  ),
  'two pages with the same url, then pop': (
    [],
    [_push('ItemRoute', args: 1), _push('ItemRoute', args: 2), _pop],
  ),
};

void main() {
  useRealBrowserHistory();
  useLiveFrames();
  setUp(rewindBrowserHistory);

  // The system back's walk of each case, kept for the runs that follow.
  final systemBack = <String, List<String>>{};

  // Steps: open the pages over Home, make the call, then press the browser's
  // back button down to the first entry and its forward button up again.
  // Each case runs once with the browser landing before the next frame and
  // once with the frame first.
  for (final MapEntry(key: name, value: (opens, call)) in _calls.entries) {
    for (final isFrameFirst in [false, true]) {
      testWidgets('On web, after $name the back button shows the pages the '
          'system back shows${isFrameFirst ? ', with the frame before the '
                    'browser lands' : ''}', (tester) async {
        await expectNativeWalk(
          tester,
          opens: opens,
          calls: [call],
          isFrameFirst: isFrameFirst,
          systemBack: systemBack[name] ??= await systemBackWalk(
            tester,
            opens: opens,
            calls: [call],
          ),
        );
      });
    }
  }

  // Steps: the same for several calls. They are made a frame apart, in one
  // turn, microtasks apart, and 30 ms apart with no frame between.
  for (final MapEntry(key: name, value: (opens, calls)) in _sequences.entries) {
    for (final (label, gap) in [
      ('a frame apart', WalkGap.frame),
      ('in one turn', WalkGap.none),
      ('microtasks apart', WalkGap.microtasks),
      ('30 ms apart with no frame', WalkGap.time),
    ]) {
      for (final isFrameFirst in [false, true]) {
        testWidgets('On web, after $name, $label, the back button shows the '
            'pages the system back shows${isFrameFirst ? ', with the frame '
                      'before the browser lands' : ''}', (tester) async {
          await expectNativeWalk(
            tester,
            opens: opens,
            calls: calls,
            gap: gap,
            isFrameFirst: isFrameFirst,
            systemBack: systemBack[name] ??= await systemBackWalk(
              tester,
              opens: opens,
              calls: calls,
            ),
          );
        });
      }
    }
  }
}
