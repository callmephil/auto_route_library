import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_sequences.dart';
import 'history_test_browser.dart';
import 'native_history_model.dart';
import 'router_test_utils.dart';

// The steps of the random sequence test of the web history, the generator
// that makes them from a seed, and the check that runs them on
// HistoryRouter and TestHistoryBrowser and compares each step with
// NativeHistoryModel.

enum HistoryStepKind { push, replace, pop, popUntil, tab, go, guard, answer }

/// One step: a call on the router, a browser move, or a guard that answers
/// late. Its toString is the Dart source that makes it again.
class HistoryStep {
  const new push(this.name) : kind = .push, delta = 0, logsIn = false;
  const new replace(this.name) : kind = .replace, delta = 0, logsIn = false;
  const new pop() : kind = .pop, name = '', delta = 0, logsIn = false;

  /// Closes the pages above the latest page named [name].
  const new popUntil(this.name) : kind = .popUntil, delta = 0, logsIn = false;

  /// Changes the tab of the tabs page on top to the tab number [delta].
  const new tab(this.delta) : kind = .tab, name = '', logsIn = false;

  /// The user moves [delta] entries: the back button is -1, the forward
  /// button 1.
  const new go(this.delta) : kind = .go, name = '', logsIn = false;

  /// Pushes GuardedRoute, whose guard shows LoginRoute until it answers.
  const new guard() : kind = .guard, name = '', delta = 0, logsIn = false;
  const new answer({required this.logsIn})
    : kind = .answer,
      name = '',
      delta = 0;

  final HistoryStepKind kind;
  final String name;
  final int delta;
  final bool logsIn;

  @override
  String toString() => switch (kind) {
    .push => "HistoryStep.push('$name')",
    .replace => "HistoryStep.replace('$name')",
    .pop => 'HistoryStep.pop()',
    .popUntil => "HistoryStep.popUntil('$name')",
    .tab => 'HistoryStep.tab($delta)',
    .go => 'HistoryStep.go($delta)',
    .guard => 'HistoryStep.guard()',
    .answer => 'HistoryStep.answer(logsIn: $logsIn)',
  };
}

String _tabUrl(int tab) => tab == 0 ? '/tabs/first' : '/tabs/second';

const _urls = {
  'HomeRoute': '/',
  'ARoute': '/a',
  'BRoute': '/b',
  'CRoute': '/c',
  'TabsRoute': '/tabs/first',
  'LoginRoute': '/login',
  'GuardedRoute': '/g',
};

final Map<String, String> _names = {
  for (final MapEntry(:key, :value) in _urls.entries) value: key,
};

String _routeName(String url) =>
    url.startsWith('/tabs/') ? 'TabsRoute' : (_names[url] ?? url);

// The text of the page at [url], as HistoryRouter builds it.
String _pageText(String url) => switch (url) {
  '/tabs/first' => 'FirstTab',
  '/tabs/second' => 'SecondTab',
  _ => _routeName(url),
};

void _applyTo(NativeHistoryModel model, HistoryStep step) {
  switch (step.kind) {
    case .push:
      model.push(_urls[step.name]!);
    case .replace:
      model.replace(_urls[step.name]!);
    case .pop:
      model.pop();
    case .popUntil:
      model.popTo(
        model.stack.map(_routeName).toList().lastIndexOf(step.name) + 1,
      );
    case .tab:
      model.changeTop(_tabUrl(step.delta));
    case .go:
      model.go(step.delta);
    case .guard:
      model.push('/login');
    case .answer:
      step.logsIn ? model.replace('/g') : model.pop();
  }
}

// xorshift32, every result kept to 32 bits, so a seed gives the same
// numbers on the VM and on the web.
class _Random {
  new(int seed) : _state = (seed * 2654435761 + 1) & _mask {
    if (_state == 0) _state = 1;
  }

  static const _mask = 0xFFFFFFFF;
  int _state;

  int next(int max) {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    _state = x & _mask;
    return _state % max;
  }
}

// Whether a landing on the entry [delta] entries away opens GuardedRoute
// again. Its guard is then asked again, which is the app's rule and not
// native history: the model leaves it out.
bool _opensGuarded(NativeHistoryModel model, int delta) {
  final from = model.stack;
  final to = model.stackAt(delta);
  var same = 0;
  while (same < from.length &&
      to.elementAtOrNull(same) == from.elementAtOrNull(same)) {
    same++;
  }
  return to.skip(same).contains('/g');
}

/// The steps for [seed]: 5 to 30 steps, each one the app or the user can
/// take from where the steps before it leave the app. The same seed always
/// gives the same steps.
List<HistoryStep> historySteps(int seed) {
  final random = _Random(seed);
  final model = NativeHistoryModel();
  final count = 5 + random.next(26);
  final steps = <HistoryStep>[];
  while (steps.length < count) {
    final step = steps.lastOrNull?.kind == .guard
        ? HistoryStep.answer(logsIn: random.next(2) == 0)
        : _nextStep(random, model);
    if (step == null || _knownIssue(model, step) != null) continue;
    steps.add(step);
    _applyTo(model, step);
  }
  return steps;
}

/// Whether the app and the user can take [steps] one after the other, as
/// [historySteps] makes them, with no step that a known issue fails on
/// unless [skipsKnownIssues] is false.
bool isValidHistory(List<HistoryStep> steps, {bool skipsKnownIssues = true}) {
  final model = NativeHistoryModel();
  for (final (number, step) in steps.indexed) {
    final waits = steps.take(number).lastOrNull?.kind == .guard;
    if (waits != (step.kind == .answer) ||
        !_canTake(model, step) ||
        (skipsKnownIssues && _knownIssue(model, step) != null)) {
      return false;
    }
    _applyTo(model, step);
  }
  return true;
}

bool _canTake(NativeHistoryModel model, HistoryStep step) {
  final names = model.stack.map(_routeName).toList();
  return switch (step.kind) {
    .push || .guard || .answer => true,
    .pop || .replace => model.canPop,
    .tab =>
      model.shown.startsWith('/tabs/') && model.shown != _tabUrl(step.delta),
    // Navigator.popUntil stops at the first page from the top that matches.
    .popUntil =>
      names.contains(step.name) &&
          names.indexOf(step.name) < names.length - 1 &&
          !names.skip(names.indexOf(step.name) + 1).contains(step.name),
    // A landing on an entry whose pages a replace has changed since shows
    // that entry's own saved pages in the model, as RESEARCH.md's design R
    // plans; the web history today puts its page over the open ones.
    .go =>
      model.canGo(step.delta) &&
          model.agreesWith(step.delta) &&
          !_opensGuarded(model, step.delta),
  };
}

String _pushed(_Random random) => switch (random.next(4)) {
  0 => 'ARoute',
  1 => 'BRoute',
  2 => 'CRoute',
  _ => 'TabsRoute',
};

HistoryStep? _nextStep(_Random random, NativeHistoryModel model) {
  final names = model.stack.map(_routeName).toList();
  final roll = random.next(100);
  final step = switch (roll) {
    < 25 => HistoryStep.push(_pushed(random)),
    < 37 => const HistoryStep.pop(),
    < 45 => HistoryStep.replace(_pushed(random)),
    < 55 => HistoryStep.tab(random.next(2)),
    < 63 => HistoryStep.popUntil(
      names.elementAtOrNull(random.next(names.length)) ?? '',
    ),
    < 75 => const HistoryStep.go(-1),
    < 85 => const HistoryStep.go(1),
    < 95 => HistoryStep.go(
      (random.next(2) == 0 ? -1 : 1) * (2 + random.next(3)),
    ),
    _ => const HistoryStep.guard(),
  };
  return _canTake(model, step) ? step : null;
}

// The issue number of a known open bug that [step] runs into from where
// [model] stands, if any. The generator leaves such a step out, so the test
// stays green until that issue is fixed; then its line here goes.
int? _knownIssue(NativeHistoryModel model, HistoryStep step) =>
    switch (step.kind) {
      // A jump forward over several entries removes the entries between and
      // ahead.
      .go when step.delta > 1 => 41,
      // A forward press onto an entry whose url an earlier entry also has
      // moves the browser back to that earlier entry.
      .go
          when step.delta > 0 &&
              model.urls
                  .take(model.index)
                  .contains(
                    model.urls.elementAtOrNull(model.index + step.delta),
                  ) =>
        66,
      // replace of a tabs page by its own route keeps the tab and the entries
      // of the old page.
      .replace
          when model.shown.startsWith('/tabs/') && step.name == 'TabsRoute' =>
        50,
      // The entries of two open tabs pages of one route mix up.
      .push || .replace
          when step.name == 'TabsRoute' &&
              model.stack
                  .take(model.stack.length - (step.kind == .push ? 0 : 1))
                  .any((url) => url.startsWith('/tabs/')) =>
        65,
      .push ||
      .replace ||
      .pop ||
      .popUntil ||
      .tab ||
      .go ||
      .guard ||
      .answer => null,
    };

/// Runs [steps] on HistoryRouter and TestHistoryBrowser, a frame apart, and
/// after each step expects the entries, the entry the browser stands on and
/// the page shown that [NativeHistoryModel] gives. On a failure it removes
/// each step it can while the steps still fail, and prints what is left.
Future<void> expectNativeHistory(
  WidgetTester tester,
  List<HistoryStep> steps, {
  int? seed,
}) async {
  final failure = await _failure(tester, steps);
  if (failure == null) return;
  var (failedAt, message) = failure;
  var failing = steps.take(failedAt + 1).toList();
  final skipsKnownIssues = isValidHistory(failing);
  // Removes one step, or two in a row, as a guard and its answer, at a time.
  for (var number = failing.length - 2; number >= 0; number--) {
    for (final count in [1, 2]) {
      if (number + count >= failing.length) continue;
      final fewer = [...failing]..removeRange(number, number + count);
      if (!isValidHistory(fewer, skipsKnownIssues: skipsKnownIssues)) {
        continue;
      }
      final fewerFailure = await _failure(tester, fewer);
      if (fewerFailure == null) continue;
      (failedAt, message) = fewerFailure;
      failing = fewer.take(failedAt + 1).toList();
      number = math.min(number, failing.length - 1);
      break;
    }
  }
  // Leaves no app open for the leak check after the test.
  await tester.pumpWidget(const SizedBox());
  fail(
    '${seed == null ? 'The steps fail' : 'Seed $seed fails'}. $message\n'
    'The shortest failing steps found, to paste into a test:\n'
    '  await expectNativeHistory(tester, const [\n'
    '${[for (final step in failing) '    $step,'].join('\n')}\n'
    '  ]);',
  );
}

// The number of the first step after which the app is not native, and how.
Future<(int, String)?> _failure(
  WidgetTester tester,
  List<HistoryStep> steps,
) async {
  await tester.pumpWidget(const SizedBox());
  final browser = TestHistoryBrowser()..reportLandingsTo(tester);
  final router = HistoryRouter(
    isGuarded: false,
    // The test's clock runs through every animation at once; the browser of
    // a test lands late, never too late.
    history: (stack) => BrowserNavigationHistory(
      stack,
      browser,
      landingLimit: const Duration(hours: 1),
    ),
  );
  addTearDown(router.navigationHistory.dispose);
  await pumpRouterConfigApp(tester, router.config());
  await browser.settle(tester);
  final model = NativeHistoryModel();
  for (final (number, step) in steps.indexed) {
    _applyTo(model, step);
    _run(router, browser, step);
    await browser.settle(tester);
    final held = [
      for (final (index, (url, _)) in browser.entries.indexed)
        '${index == browser.index ? '>' : ''}${url.isEmpty ? '/' : url}',
    ].join(' ');
    final shown = _shownText();
    final expected = _pageText(model.shown);
    if (held == model.held && shown == expected) continue;
    return (
      number,
      'After step ${number + 1}, $step:\n'
          'The browser holds $held; native history holds ${model.held}.\n'
          'The app shows $shown; native history shows $expected.',
    );
  }
  return null;
}

void _run(HistoryRouter router, TestHistoryBrowser browser, HistoryStep step) {
  switch (step.kind) {
    case .push:
      unawaited(router.push(NamedRoute(step.name)));
    case .replace:
      unawaited(router.replace(NamedRoute(step.name)));
    case .pop:
      router.pop();
    case .popUntil:
      router.popUntil((route) => route.settings.name == step.name);
    case .tab:
      router.innerRouterOf<TabsRouter>('TabsRoute')!.setActiveIndex(step.delta);
    case .go:
      browser.didJump(step.delta);
    case .guard:
      unawaited(router.push(const NamedRoute('GuardedRoute')));
    case .answer:
      final resolver = router.loginResolver!;
      step.logsIn ? resolver.next() : resolver.reject();
  }
}

// The text of each page the user sees.
String _shownText() => [
  for (final element in find.byType(Text).evaluate())
    (element.widget as Text).data!.trim(),
].join(', ');
