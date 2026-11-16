import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';

/// How a [HeldGuard] answers an ask that has not been answered by hand yet.
enum HeldGuardMode {
  /// `onNavigation` is `async` and awaits the test's answer: the guard's call
  /// stays open until the test answers. This is a guard that does
  /// `await somethingSlow(); resolver.next();`.
  holdsCall,

  /// `onNavigation` returns at once and the test answers later, as a guard
  /// does that waits for a callback or a stream event. The router sees a
  /// finished call whose resolver is still open.
  ///
  /// Also the way to make a guard that answers nothing at all: never answer
  /// the ask.
  returnsAtOnce,

  /// The call answers yes before it returns. Nothing is held.
  answersYes,

  /// The call answers no before it returns. Nothing is held.
  answersNo,
}

/// One time the router asked a [HeldGuard].
///
/// The test answers it with [allow], [reject], [redirectUntil] or [redirect].
/// An ask is answered once; a second answer throws a [StateError], so a test
/// can't count an answer twice by mistake.
class HeldAsk {
  new _(this.number, this.resolver, this.router, this._isHeld);

  /// Counts the asks of the guard from 1, in the order they came.
  final int number;

  /// The resolver the router gave the guard for this ask.
  final NavigationResolver resolver;

  /// The router the guard was asked in. For a guard of a nested route this
  /// is the nested router, not the root.
  final StackRouter router;

  final bool _isHeld;
  final _call = Completer<FutureOr<void> Function()>();
  bool _isAnswered = false;

  /// Whether the test has not answered this ask yet.
  ///
  /// Not whether the router still waits: the router may have given up on the
  /// ask (a newer navigation, a closed router) while this stays true. Asks
  /// the guard answered itself ([HeldGuardMode.answersYes] and
  /// [HeldGuardMode.answersNo]) are never waiting.
  bool get isWaiting => !_isAnswered;

  /// Whether the guard's call is still open for this ask, which is so only
  /// in [HeldGuardMode.holdsCall] and only until the answer. It says nothing
  /// about the router's wait.
  bool get isCallOpen => _isHeld && !_isAnswered;

  /// Lets the navigation through: `resolver.next()`.
  Future<void> allow() => _answer(resolver.next);

  /// Turns the navigation down: `resolver.reject()`.
  Future<void> reject({bool goBack = false}) =>
      _answer(() => resolver.reject(goBack: goBack));

  /// Shows [target] over the page until the guard is let through:
  /// `resolver.redirectUntil(target)`.
  ///
  /// The returned future completes once the resolver's own future does, that
  /// is when [target] has closed (or at once if the router refuses the
  /// redirect). In [HeldGuardMode.holdsCall] the guard's call waits for it
  /// too. It does not let the navigation through: answer with [allow] after.
  Future<void> redirectUntil(
    PageRouteInfo target, {
    bool replace = false,
    OnNavigationFailure? onFailure,
  }) => _answer(
    () =>
        resolver.redirectUntil(target, replace: replace, onFailure: onFailure),
  );

  /// Sends the user to [target] for good and turns the navigation down: a
  /// push of [target] on the guard's router followed by `resolver.reject()`.
  ///
  /// This is not the page held back by [redirectUntil]; nothing brings the
  /// held navigation back.
  Future<void> redirect(PageRouteInfo target) => _answer(() {
    unawaited(router.push(target));
    resolver.reject();
  });

  Future<void> _answer(FutureOr<void> Function() action) {
    if (_isAnswered) {
      throw StateError('Ask $number of the held guard is answered already.');
    }
    _isAnswered = true;
    if (_isHeld) {
      // The guard's call runs the action when it wakes up.
      _call.complete(action);
      return _done.future;
    }
    return Future.sync(action);
  }

  final _done = Completer<void>();
}

/// A guard the test answers by hand, to test what happens while a guard
/// waits.
///
/// Every ask is recorded in [asks], in order, so a test can answer the second
/// before the first. Use it as a route's guard, as a guard of the root router
/// (`RootStackRouter.build(guards: [guard])`) or as a tab route's guard; it
/// is an ordinary [AutoRouteGuard].
///
/// ```dart
/// final guard = HeldGuard();
/// final router = RootStackRouter.build(
///   routes: [..., NamedRouteDef(name: 'CheckoutRoute', guards: [guard], ...)],
/// );
/// unawaited(router.push(const NamedRoute('CheckoutRoute')));
/// await tester.pump();
/// expect(guard.askCount, 1);
/// await guard.last.allow();
/// await tester.pumpAndSettle();
/// ```
class HeldGuard extends AutoRouteGuard {
  /// Makes a guard that [mode] decides for; the default holds the call.
  new({this.mode = .holdsCall});

  /// How the asks that come next are answered. Asks already recorded keep
  /// the mode they came in.
  HeldGuardMode mode;

  final _asks = <HeldAsk>[];

  /// Every ask so far, oldest first, answered or not.
  List<HeldAsk> get asks => UnmodifiableListView(_asks);

  /// How many times the router has asked, not how many wait.
  int get askCount => _asks.length;

  /// The asks the test has not answered yet, oldest first.
  List<HeldAsk> get waiting => [
    for (final ask in _asks)
      if (ask.isWaiting) ask,
  ];

  /// The oldest ask. Throws when there is none.
  HeldAsk get first =>
      _asks.firstOrNull ?? (throw StateError('The guard was not asked.'));

  /// The newest ask. Throws when there is none.
  HeldAsk get last =>
      _asks.lastOrNull ?? (throw StateError('The guard was not asked.'));

  /// From now on the call answers yes at once. Asks already waiting stay
  /// waiting.
  void answerYes() => mode = .answersYes;

  /// From now on the call answers no at once. Asks already waiting stay
  /// waiting.
  void answerNo() => mode = .answersNo;

  /// From now on the call returns at once without answering, and the ask
  /// stays open for the test, or for good if the test never answers it.
  void answerNothing() => mode = .returnsAtOnce;

  /// From now on the call stays open until the test answers.
  void holdCall() => mode = .holdsCall;

  /// Forgets the recorded asks. Does not answer them.
  void clear() => _asks.clear();

  @override
  FutureOr<void> onNavigation(NavigationResolver resolver, StackRouter router) {
    final isHeld = mode == .holdsCall;
    final ask = HeldAsk._(_asks.length + 1, resolver, router, isHeld);
    _asks.add(ask);
    switch (mode) {
      case .holdsCall:
        return _hold(ask);
      case .returnsAtOnce:
        return null;
      case .answersYes:
        ask._isAnswered = true;
        resolver.next();
      case .answersNo:
        ask._isAnswered = true;
        resolver.reject();
    }
    return null;
  }

  Future<void> _hold(HeldAsk ask) async {
    final action = await ask._call.future;
    try {
      await action();
      ask._done.complete();
    } on Object catch (error, stack) {
      ask._done.completeError(error, stack);
    }
  }

  @override
  String toString() => 'HeldGuard($askCount asks, ${mode.name})';
}
