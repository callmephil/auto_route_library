part of 'routing_controller.dart';

/// Signature for on navigation function used by [AutoRouteGuard]
typedef OnNavigation = FutureOr<void> Function(
  NavigationResolver resolver,
  StackRouter router,
);

/// A middleware for stacked routes where clients
/// can either resume or abort the navigation event
///
/// A guard of a route inside a nested router is asked by that router, once
/// the router above has let the route that holds it through. When that
/// router is built, as for an open page or a tab opened before, the tab
/// doesn't change, and the dialogs and pages over the page stay until it
/// answers, and after a rejection. A guard that puts a page of its own there
/// while it decides, such as a sign-in page, shows it: the tab shows, and
/// the pages over the page leave first. The tab stays on the page under the
/// sign-in page if the guard then rejects. When that router isn't built yet, as for a page that isn't open or a tab never
/// opened, it asks its guards only once its page or tab is in, a frame later.
/// A rejection then takes that page back off, so the stack, the url and the
/// dialogs are as before, and the page's caller gets null; the dialogs of a
/// link stay open while the guard decides. A page that is the only page of
/// its router, as when the app starts at the link, stays, on its first page.
/// So does a page whose navigation took pages off on its way in, as
/// [StackRouter.replace] and [StackRouter.replaceAll] do, which can't come
/// back: on its first page, or on the router's placeholder when the guarded
/// page is its only child.
/// A link or the app's own navigation into a tab never opened, to pages a
/// guard is asked about, builds the tab off the screen first instead, and a
/// rejection keeps the tab the user is on.
abstract class AutoRouteGuard {
  /// Default constructor
  const new();

  /// Builds a simple instance that takes in the [OnNavigation] callback
  const factory simple(OnNavigation onNavigation, {String? debugLabel}) =
      AutoRouteGuardCallback;

  /// Builds a simple instance that returns either a redirect-to route or null
  /// for no redirect
  const factory redirect(
    PageRouteInfo? Function(NavigationResolver resolver) redirect,
  ) = _AutoRouteGuardRedirectCallback;

  /// Builds a simple instance that returns either a redirect-to path or null
  /// for no redirect
  const factory redirectPath(
    String? Function(NavigationResolver resolver) redirect,
  ) = _AutoRouteGuardRedirectPathCallback;

  /// clients will call [NavigationResolver.next] to continue
  /// navigation or [NavigationResolver.reject] to abort navigation
  /// example
  /*
  class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
     if (isAuthenticated) {
       resolver.next();
     } else {
       resolver.reject();
     }
  }
}
   */
  FutureOr<void> onNavigation(NavigationResolver resolver, StackRouter router);

  @override
  String toString() => 'AutoRouteGuard($hashCode)';
}

class _AutoRouteGuardRedirectCallback extends AutoRouteGuard {
  const new(this.redirect);
  final PageRouteInfo? Function(NavigationResolver resolver) redirect;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final redirectTo = redirect(resolver);
    if (redirectTo != null) {
      final scope = router._findStackScope(redirectTo);
      unawaited(
        scope._push(
          redirectTo,
          onMatch: (match) => _redirectingResolvers[match.id] = resolver,
        ),
      );
    }
    if (redirectTo == null) {
      resolver.next();
    } else {
      resolver.reject();
    }
  }
}

class _AutoRouteGuardRedirectPathCallback extends AutoRouteGuard {
  const new(this.redirect);
  final String? Function(NavigationResolver resolver) redirect;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final redirectTo = redirect(resolver);
    if (redirectTo != null) {
      final scope = router._findPathScopeOrReportFailure<StackRouter>(
        redirectTo,
      );
      if (scope != null) {
        for (final match in scope.matches) {
          _redirectingResolvers[match.id] = resolver;
        }
        unawaited(scope.router._pushAllGuarded(scope.matches));
      }
    }
    if (redirectTo == null) {
      resolver.next();
    } else {
      resolver.reject();
    }
  }
}

/// Abstraction for an Adapter that converts
/// different listenable types e.g (streams) to a ChangeNotifier

abstract class ReevaluateListenable extends ChangeNotifier {
  /// Default constructor
  new();

  /// Builds [ReevaluateListenable] from a stream
  factory stream(Stream<Object?> stream) = _StreamReevaluateListenable;
}

class _StreamReevaluateListenable extends ReevaluateListenable {
  new(Stream<Object?> stream) {
    _streamSub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<Object?> _streamSub;

  @override
  void dispose() {
    unawaited(_streamSub.cancel());
    super.dispose();
  }
}

/// A simple implementation of [AutoRouteGuard] that
/// calls the provided [OnNavigation] function
///
/// use if there's no need to implement your own
class AutoRouteGuardCallback extends AutoRouteGuard {
  /// Default constructor
  const new(this.onNavigate, {this.debugLabel});

  /// The callback called by [AutoRouteGuard.onNavigation]
  final OnNavigation onNavigate;

  /// An optional debug name for easier identification
  final String? debugLabel;

  // Returns the callback's future, so a guard re-check can wait for an async
  // callback.
  @override
  FutureOr<void> onNavigation(
    NavigationResolver resolver,
    StackRouter router,
  ) => onNavigate(resolver, router);

  @override
  String toString() => 'AutoRouteGuardCallback(${debugLabel ?? hashCode})';
}

/// Holds how a guard resolved: [NavigationResolver.next],
/// [NavigationResolver.reject] or [NavigationResolver.overrideNext]
class ResolverResult {
  /// Default constructor
  const new({
    required this.continueNavigation,
    required this.reevaluateNext,
    required this.route,
  });

  /// Whether to resume the navigation event or abort it
  final bool continueNavigation;

  /// Whether to re-push pending routes on [StackRouter.reevaluateGuards]
  final bool reevaluateNext;

  /// Holds the route to be used in the navigation event
  final RouteMatch<Object?> route;

  //// clones this instance with the provided values
  ResolverResult copyWith({
    bool? continueNavigation,
    bool? reevaluateNext,
    RouteMatch<Object?>? route,
  }) {
    return ResolverResult(
      continueNavigation: continueNavigation ?? this.continueNavigation,
      reevaluateNext: reevaluateNext ?? this.reevaluateNext,
      route: route ?? this.route,
    );
  }
}

// The resolver whose redirect opened a route, by the route's match id: the
// redirectUntil() or the AutoRouteGuard.redirect() of the guard that sent the
// user there.
final _redirectingResolvers = Expando<NavigationResolver>(
  'redirectingResolvers',
);

// The routes of the tabs, by the resolver of a tab's guard: the guarded
// route is one of them, not of the stack router the guard runs on.
final _tabRoutesOfResolvers = Expando<RouteMatcher>('tabRoutesOfResolvers');

// Marks the resolvers of a tab's guards that a reevaluation asks, see
// [TabsRouter._reevaluateActiveTab]: a change the guard makes itself
// meanwhile starts no other round, see
// [StackRouter._composeMatchesForReevaluate].
final _tabAsksOfReevaluation = Expando<bool>('tabAsksOfReevaluation');

/// Represents a guarded navigation event
/// which can be either continued or aborted
/// used in [AutoRouteGuard.onNavigation]
class NavigationResolver {
  /// default constructor
  new(
    this._router,
    this._completer,
    this.route, {
    this.pendingRoutes = const [],
    this._isReevaluating = false,
  });
  final StackRouter _router;
  final Completer<ResolverResult> _completer;

  /// Whether the navigation event is triggered
  /// by [StackRouter.reevaluateGuards]
  bool get isReevaluating => _isReevaluating;

  bool _isReevaluating = false;

  /// The route being processing by the guard
  final RouteMatch<Object?> route;

  /// Helper to get [RouteMatch.name]
  String get routeName => route.name;

  /// If there are more that one route in
  /// the navigation even pending routes will
  /// be the routes that's waiting to be processed by guard
  ///
  /// e.g if we pushAll[Route1,Route2,Route3]
  /// the first route to be processed is Route1 and that's assigned to [route]
  /// and pending routes will contain [Route2, Route3]
  ///
  /// when we process  Rout2 next pending routes will contain `Route3` only
  final List<RouteMatch<Object?>> pendingRoutes;

  /// The context of the router that runs this guard, which sits above that
  /// router's navigator.
  ///
  /// A guard reads through it what is provided above the router, such as a
  /// widget around `MaterialApp.router`, or around the `AutoRouter` of the
  /// parent page for a nested route.
  ///
  /// It is set once the router's widget is built, and the guards of the app's
  /// first page, on the root router and in nested routers alike, already run
  /// after that. Only a navigation started before the router's widget is
  /// built, such as a `push` before `runApp`, has no context: reading it then
  /// fails, in a debug build with "Router is not mounted".
  BuildContext get context {
    final context = _router.globalRouterKey.currentContext;
    assert(context != null, 'Router is not mounted');
    return context!;
  }

  /// Lets the navigation continue to [route].
  ///
  /// Call this, [reject] or [overrideNext] once per navigation.
  void next() => _resolve(continueNavigation: true, reevaluateNext: true);

  /// Stops the navigation: [route] is not opened.
  ///
  /// With [goBack], the router also goes back, which reverts the url when the
  /// navigation came from it, such as a link opened in the browser.
  ///
  /// With [reevaluateNext] false, the routes pending after [route] are not
  /// pushed again when `RoutingController.reevaluateGuards` runs this guard.
  void reject({bool goBack = false, bool reevaluateNext = true}) {
    _resolve(continueNavigation: false, reevaluateNext: reevaluateNext);
    if (goBack) {
      _router.back();
    }
  }

  void _resolve({
    required bool continueNavigation,
    required bool reevaluateNext,
  }) {
    assert(!isResolved, 'Make sure `resolver.next()` is only called once.');
    _complete(
      ResolverResult(
        continueNavigation: continueNavigation,
        reevaluateNext: reevaluateNext,
        route: route,
      ),
    );
  }

  // The result the guard resolved with, known at once, before [future]
  // completes, so a tab change a guard decides at once stays synchronous.
  ResolverResult? _result;

  void _complete(ResolverResult result) {
    _isAnswerStale = _isAnswerFromBeforeChange;
    _result = result;
    _completer.complete(result);
  }

  /// Overrides the current route with the provided values
  ///
  /// overridden routes will not be processed by the same guard again
  /// in the same navigation event
  void overrideNext({
    List<PageRouteInfo>? children,
    Object? args,
    Map<String, dynamic>? queryParams,
    String? fragment,
    bool reevaluateNext = true,
  }) {
    assert(!isResolved, 'Make sure `resolver.next()` is only called once.');
    final overrides = RouteOverrides(
      children: children,
      args: args,
      queryParams: queryParams,
      fragment: fragment,
    );
    final overriddenRoute = overrides.override(
      route,
      _tabRoutesOfResolvers[this] ?? _router.matcher,
    );
    _complete(
      ResolverResult(
        continueNavigation: true,
        reevaluateNext: reevaluateNext,
        route: overriddenRoute,
      ),
    );
  }

  bool _isRedirecting = false;

  /// Temporary redirect to another route until the [_completer] is resolved
  ///
  /// Calling resolver.next() or resolver.reject()
  /// will remove the redirected route and mark it for replace
  /// in browser history
  ///
  /// This is typically used like follows
  ///
  /// onNavigation(resolver, router) {
  ///    if (isAuthenticated) {
  ///      resolver.next();
  ///    } else {
  ///      resolver.redirectUntil(LoginRoute());
  ///    }
  ///  }
  ///
  /// With [replace], [target] takes the place of the page on top, which
  /// leaves once the guards of [target] let it through. A [target] that
  /// doesn't open, as one a guard rejects or one no route matches, leaves
  /// that page on the stack.
  ///
  /// The returned future completes once [route] is closed, whether by
  /// [next] or by a pop, and at once when a redirect is already running or
  /// [route] can't be opened.
  Future<void> redirectUntil(
    PageRouteInfo target, {
    OnNavigationFailure? onFailure,
    bool replace = false,
  }) async {
    if (_isRedirecting) return;
    final reevaluatedRoute = route;
    // The app took the page off while this guard decided whether it may
    // stay: no page is left to show [target] for.
    if (_router._wasTakenOffDuringReevaluation(reevaluatedRoute)) {
      if (!isResolved) reject();
      return;
    }
    _isRedirecting = true;
    // keep the page being reevaluated under the redirect route so its state is
    // preserved
    if (reevaluatedRoute is ReevaluatableRouteMatch<Object?, Object?> &&
        !_router._pages.contains(reevaluatedRoute.currentPage)) {
      _router._pages.add(reevaluatedRoute.currentPage);
    }
    // The guard's check is over: from here on it waits behind [target],
    // whether its call returns now or awaits this redirect until [target]
    // closes.
    _endCheck();
    await _router._redirect(
      target,
      onFailure: onFailure,
      replace: replace,
      isReevaluating: reevaluatedRoute is ReevaluatableRouteMatch,
      onMatch: (scope, match) =>
          unawaited(_removeRedirectOnceResolved(scope, match)),
    );
    if (!_completer.isCompleted) {
      reject();
    }
  }

  // Once this resolver is resolved, the redirect route that [redirectUntil]
  // pushed leaves the stack.
  Future<void> _removeRedirectOnceResolved(
    StackRouter scope,
    RouteMatch<Object?> match,
  ) async {
    _redirectingResolvers[match.id] = this;
    await _completer.future;
    _isRedirecting = false;
    // A router that left with its page, as when the user leaves a shell
    // while its guard shows the redirect, took the redirect route with it:
    // nothing is taken off a disposed router, and the url keeps no mark.
    if (scope._isDisposed) return;
    final routeData = scope.stackData.firstWhereOrNull(
      (e) => e.matchId == match.id,
    );
    if (routeData != null) {
      scope
        ..markUrlStateForReplace()
        .._removeRoute(match);
      // complete the pop completer with null result
      routeData.onPopInvoked(null);
    }
  }

  /// Helpful for when you want to revert to the previous
  /// url back can not navigate
  ///
  /// The same as [next]; `reject(goBack: true)` stops the navigation and goes
  /// back.
  void nextOrBack() => next();

  // Rejects [route] when the guards that redirected the user here opened the
  // same route earlier in this chain of redirects, which would repeat without
  // end.
  bool _didReportRedirectLoop() {
    final chain = <RouteMatch<Object?>>[];
    for (
      var by = _redirectingResolvers[route.id];
      by != null;
      by = _redirectingResolvers[by.route.id]
    ) {
      chain.insert(0, by.route);
      final isSame =
          by.route.name == route.name && by.route.fullPath == route.fullPath;
      if (isSame) {
        _reportLoop([...chain, route]);
        reject();
        return true;
      }
      // A re-check starts its own chain; the redirects that once opened its
      // route are over.
      if (by.isReevaluating) break;
    }
    return false;
  }

  void _reportLoop(List<RouteMatch<Object?>> loop) {
    final name = route.name;
    final names = loop.map((match) => match.name).join(' → ');
    _router.root._launchAsks?.hasReportedLoop = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts([
          if (loop.length == 2)
            ErrorSummary('A guard redirected $name to itself.')
          else
            ErrorSummary('Guards redirected in a loop: $names.'),
          ErrorDescription(
            '$name was opened by the redirect of a guard, and guards '
            'redirected the user to $name again, which '
            'would repeat without end. $name is not opened.',
          ),
          ErrorHint(
            'A guard in RootStackRouter.guards runs for every route, '
            'including the one it redirects to. '
            'Let a route in the loop through, e.g. call resolver.next() '
            'when resolver.routeName is $name.',
          ),
        ]),
        library: 'auto_route',
      ),
    );
  }

  /// Whether [_completer] is completed
  /// see [Completer.isCompleted]
  bool get isResolved => _completer.isCompleted;

  /// The future that will be completed by [next], [reject] or [overrideNext]
  Future<ResolverResult> get future => _completer.future;

  // Pending while the guard runs its check: from its call until the call
  // returns or the guard starts a redirect, whichever comes first. A guard
  // that awaits its redirect returns only once the page it shows has closed,
  // and is no longer checking meanwhile: a reevaluation asks it again, as it
  // asks one that started its redirect and returned.
  Completer<void>? _waitingCompleter;

  void _endCheck() {
    final waiting = _waitingCompleter;
    _waitingCompleter = null;
    waiting?.complete();
  }

  /// Checks the provided [guard] and waits for it to complete
  ///
  /// If there's an ongoing guard check, it waits for it to complete first
  /// before checking the provided [guard]
  /// returns the [ResolverResult] of the guard check
  Future<ResolverResult> checkGuard(AutoRouteGuard guard, StackRouter router) =>
      _checkGuard(guard, router);

  // Holds, in the zone a guard's call runs in, the resolver the guard was
  // given. What that call does can then be told as the guard's own, also
  // after an await and in what the call starts: the pages it puts on a
  // stack, see [_reportPageGoesOn], and a change it makes to the listenable
  // the guards are asked again for, see [_isOwnCodeRunning].
  static final _askedZone = Object();

  // Holds, in the zone of each call of the guard, that call's number, see
  // [_calls]: the answer a call's code gives is known as that call's.
  static final _askedCallZone = Object();

  // How many times the guard was called with this resolver: once when it is
  // asked, then once each time a reevaluation asks it again, see
  // [_checkGuard].
  var _calls = 0;

  // The last call before the latest change of the state the guards are asked
  // again for, see [_markAnswersStale]: an answer from it or an earlier call
  // is from before that change.
  int? _staleUpTo;

  // Called when that state changes while the guard decides, not by its own
  // code: the answers of the calls made so far are from before the change.
  // An answer of a later call, made after the change, is not.
  void _markAnswersStale() => _staleUpTo = _calls;

  // Whether the answer given now is from before the latest change: one from a
  // call up to [_staleUpTo], or from code outside every call of the guard,
  // which can't be told from a call made before the change.
  bool get _isAnswerFromBeforeChange {
    final upTo = _staleUpTo;
    if (upTo == null) return false;
    final call = _isOwnCodeRunning ? Zone.current[_askedCallZone] : null;
    return call is! int || call <= upTo;
  }

  // Whether the code that runs now is the guard's that was given this
  // resolver.
  bool get _isOwnCodeRunning => identical(Zone.current[_askedZone], this);

  // Whether the guard's answer is from before a change of the state the
  // guards are asked again for, a change not its own, see
  // [_markAnswersStale]: a yes is then dropped and the guard asked anew, see
  // [StackRouter._canNavigate]. Known once the guard has answered.
  bool _isAnswerStale = false;

  // Whether the guard let go of the page it was asked about, see
  // [StackRouter._letGoOfGuard].
  bool _hasLetGo = false;

  // Whether this guard decides about a navigation that a router above waits
  // on, see [_letInAboveZone]: a reevaluation waits for its check.
  bool _letsInNavigationAbove = false;

  // Whether the page or tab this guard let go of left for good, as one that
  // replaceAll replaced: no change asks the guard again, and a stale yes of
  // its is not asked again, see [StackRouter._dropLetGoGuards].
  bool _isDropped = false;

  // Whether a reevaluation asked this navigation's guard again without
  // waiting for its answer, since its call had returned without one: no
  // later reevaluation waits for that ask either, see
  // [StackRouter._composeMatchesForReevaluate].
  bool _isAskedAgainApart = false;

  // Whether the guard has put a page of its own on a stack since it was
  // asked, as one that awaits its own push of a login page does, or a
  // pageless route, as one that asks the user in a dialog does. From then on
  // it waits on the user and answers from what happens there, as a guard
  // behind its redirect does: a change meanwhile, such as the sign-in on
  // that page, leaves its answer fresh.
  bool _isWaitingOnUser = false;

  // Told with the router each time code of the guard puts a page on a stack
  // while the guard has not answered, see [_checkGuard].
  ValueChanged<StackRouter>? _onShowsPage;

  // Called by [router] right before it adds a new page. When the code that
  // adds it is a guard's that has not answered, such as its redirectUntil or
  // a push of its own login page, also after an await and whether or not the
  // guard awaits that page, the navigation the guard decides about hears of
  // it. A page the app adds meanwhile is not the guard's.
  static void _reportPageGoesOn(StackRouter router) {
    final asked = Zone.current[_askedZone];
    if (asked is NavigationResolver && !asked.isResolved) {
      asked
        .._isWaitingOnUser = true
        .._onShowsPage?.call(router);
    }
  }

  // Called by a router's [PagelessRoutesObserver] as a pageless route, such
  // as a dialog, goes on its navigator. When the code that shows it is a
  // guard's that has not answered, as one that asks the user in a dialog,
  // the guard waits on the user from then on. Unlike a page, a dialog takes
  // the place of no page, so the navigation the guard decides about is not
  // told.
  static void _reportPagelessRouteGoesOn(Route<Object?> _) {
    final asked = Zone.current[_askedZone];
    if (asked is NavigationResolver && !asked.isResolved) {
      asked._isWaitingOnUser = true;
    }
  }

  // [checkGuard], with [onLeftUndecided] called when [guard] returns without
  // having resolved: it holds the navigation until it resolves later, behind
  // a redirect it started or with nothing shown. When [onLeftUndecided] says
  // the navigation let go of the guard's page, the guard no longer counts as
  // in progress, see [StackRouter._letGoOfGuard]. And with [onShowsPage]
  // called each time [guard] puts a page of its own on a stack before it has
  // resolved, at the step the page goes on.
  Future<ResolverResult> _checkGuard(
    AutoRouteGuard guard,
    StackRouter router, {
    _GuardHoldsCallback? onLeftUndecided,
    ValueChanged<StackRouter>? onShowsPage,
  }) async {
    if (_didReportRedirectLoop()) return await future;
    // Several reevaluations can wait for the same check; each takes its own
    // turn.
    while (_waitingCompleter != null) {
      await _waitingCompleter!.future;
      if (isResolved) return await future;
    }
    final waiting = _waitingCompleter = Completer<void>();
    // Kept for a later call of this guard too, as a reevaluation makes.
    _onShowsPage = onShowsPage ?? _onShowsPage;
    final call = ++_calls;
    try {
      await runZoned(
        () => guard.onNavigation(this, router),
        zoneValues: {_askedZone: this, _askedCallZone: call},
      );
    } finally {
      // Not when a redirect ended this check and a later one began meanwhile.
      if (identical(_waitingCompleter, waiting)) _endCheck();
    }
    if (!isResolved &&
        (onLeftUndecided?.call(
              isWaitingOnUser: _isRedirecting || _isWaitingOnUser,
            ) ??
            false)) {
      _router._letGoOfGuard(this);
    }
    return await future;
  }
}

/// Holds overridable route values
class RouteOverrides {
  /// Default constructor
  const new({this.children, this.args, this.queryParams, this.fragment});

  /// The override value of `PageRouteInfo.children`
  final List<PageRouteInfo>? children;

  /// The override value of [PageRouteInfo.args]
  ///
  /// it must be the same args type generated by the corresponding page's
  /// constructor
  final Object? args;

  /// The override value of [PageRouteInfo.queryParams]
  final Map<String, dynamic>? queryParams;

  /// The override value of [PageRouteInfo.fragment]
  final String? fragment;

  /// Builds a new [PageRouteInfo] with the provided overrides
  RouteMatch<Object?> override(
    RouteMatch<Object?> route,
    RouteMatcher matcher,
  ) {
    final matches = <RouteMatch<Object?>>[];
    if (children != null) {
      final coll = matcher.collection.subCollectionOf(route.name);
      final subMatcher = RouteMatcher(coll);
      for (final child in children!) {
        final match = subMatcher.matchByRoute(child);
        if (match == null) {
          throw FlutterError(
            'Failed to navigate to overridden child '
            '${child.routeName}.\nPlease make sure the route is declared '
            'as a child of ${route.name}',
          );
        }
        matches.add(match);
      }
    }
    return route.copyWith(
      args: args,
      queryParams: switch (queryParams) {
        final query? => Parameters(withoutEmptyQueryValues(query)),
        null => null,
      },
      children: matches.isEmpty ? null : matches,
      fragment: fragment,
    );
  }
}
