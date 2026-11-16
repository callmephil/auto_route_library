// `extends Object?` is not unnecessary: without it, a type argument an app
// leaves out is inferred as `dynamic`, not `Object?`.
// ignore_for_file: avoid-unnecessary-extends

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/matcher/route_matcher.dart';
import 'package:auto_route/src/route/auto_route.dart';
import 'package:auto_route/src/router/transitions/auto_page_route_builder.dart';
import 'package:auto_route/src/utils.dart';
import 'package:auto_route/src/utils/collection.dart';
import 'package:collection/collection.dart' hide ListExtensions;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

part '../../route/route_data.dart';
part 'auto_route_guard.dart';
part 'auto_route_leave_listener.dart';
part 'auto_router_delegate.dart';
part 'root_stack_router.dart';
part 'routes_restoration.dart';

/// Signature of a predicate to select [RouteData]
typedef RouteDataPredicate = bool Function(RouteData<Object?> route);

/// Signature of a callback used by declarative
typedef OnNestedNavigateCallBack = void Function(
  List<RouteMatch<Object?>> routes,
);

/// Signature of a callback used in declarative routing
typedef RoutesBuilder = List<PageRouteInfo> Function(
  PendingRoutesHandler handler,
);

/// Signature of a callback to report route pop events
typedef RoutePopCallBack = void Function(
  RouteMatch<Object?> route,
  Page<Object?> page,
);

/// Signature of a callback used in declarative routing
/// to report url state changes
typedef OnNavigateCallBack = void Function(UrlState tree);

/// Signature for a builder that returns a list of [NavigatorObserver]
typedef NavigatorObserversBuilder = List<NavigatorObserver> Function();

/// An Abstraction for an object that manages
/// page navigation
abstract class RoutingController with ChangeNotifier {
  final _childControllers = <RoutingController>[];
  bool _shouldIgnorePopCompleter = false;

  /// Whether [AutoRoutePage] should await for pop-completer
  bool get ignorePopCompleters => root._shouldIgnorePopCompleter;

  @visibleForTesting
  set ignorePopCompleters(bool value) {
    root._shouldIgnorePopCompleter = value;
  }

  /// This key is passed to the router scope
  /// it's used to provide build context inside auto_route guards instead of
  /// using `navigatorKey.currentContext` because it maybe null at times
  final GlobalObjectKey<State<StatefulWidget>> globalRouterKey =
      GlobalObjectKey(UniqueKey());

  /// Holds track of the list of attached child controllers
  List<RoutingController> get childControllers => _childControllers;

  // Called on hot reload. A router that copied its routes from its parent
  // reads them again, so routes added or removed since it was built match.
  void _reassemble() {
    for (final child in _childControllers) {
      child._reassemble();
    }
  }

  // The routes of [name] in this controller's routes, if it still has
  // children after a hot reload.
  RouteCollection? _reassembledSubCollection(String name) {
    final route = routeCollection[name];
    return route != null && route.hasSubTree
        ? routeCollection.subCollectionOf(name)
        : null;
  }

  final List<AutoRoutePage<Object?>> _pages = [];

  /// The instance of [NavigationHistory] to be used by this router
  ///
  /// There's only one [NavigationHistory] instance in the whole
  /// hierarchy that's built inside of the [root] navigator
  ///
  /// sub-controllers will use that instance instead of creating their own
  NavigationHistory get navigationHistory => root.navigationHistory;

  /// See [NavigationHistory.markUrlStateForReplace]
  void markUrlStateForReplace() => navigationHistory.markUrlStateForReplace();

  bool _isMarkedForDataUpdate = false;

  /// Adds the given controller to the list of [childControllers]
  void attachChildController(RoutingController childController) {
    assert(
      !_childControllers.contains(childController),
      'This child controller is already attached.',
    );
    _childControllers.add(childController);
  }

  /// removes the given controller from the list of [childControllers]
  void removeChildController(RoutingController childController) {
    _childControllers.remove(childController);
  }

  RoutingController? _topInnerControllerOf(Key routeKey) {
    return _childControllers.lastWhereOrNull((c) => c.key == routeKey);
  }

  // The nested router of the page [data] belongs to, found by the page's
  // match id: two pages can share a route key, as two AutoTabsRouter tabs do
  // when both are children of the same parent route, and as a page does with
  // the one it replaced while that one still animates out with its own nested
  // router. A page that takes over the nested router of the page it replaced
  // takes over its match id too.
  RoutingController? _innerControllerOfPage(RouteData<Object?>? data) {
    if (data == null) return null;
    return _innerControllerOfMatch(data.matchId);
  }

  RoutingController? _innerControllerOfMatch(Key matchKey) {
    return _childControllers.lastWhereOrNull((c) => c.matchId == matchKey);
  }

  // The pages open in this router, in the shape a nested router opens from
  // its route's pending children: each holds the pages of its own nested
  // router, and a tabs router lists all its tabs, the active one last. Their
  // guards already let them open, so they aren't checked again.
  List<RouteMatch<Object?>> _openMatches() {
    final pages = _pages.map((page) => page.routeData).toList();
    if (this case final TabsRouter tabs when tabs.activeIndex < pages.length) {
      pages.add(pages.removeAt(tabs.activeIndex));
    }
    return [
      for (final data in pages)
        data.route.copyWith(
          queryParams: data._ownQueryParams,
          fragment: data._ownFragment,
          children: switch (_innerControllerOfMatch(data.matchId)) {
            null => data.pendingChildren,
            final child when child.managedByWidget => null,
            final child => child._openMatches(),
          },
          evaluatedGuards: data.route.guards,
        ),
    ];
  }

  /// Helper to access [NavigationHistory.urlState]
  UrlState get urlState => navigationHistory.urlState;

  /// Helper to access `NavigationHistory.urlState.path`
  String get currentPath => urlState.path;

  /// Helper to access `NavigationHistory.urlState.url`
  String get currentUrl => urlState.url;

  /// Notify this controller for changes then notify root controller
  /// if they're not the same
  ///
  /// if needed rebuild the url
  void notifyAll({bool forceUrlRebuild = false}) {
    notifyListeners();
    if (forceUrlRebuild || !isRouteDataActive(current)) {
      navigationHistory.rebuildUrl();
    }
    // The root hears of every change, to save the pages of nested routers
    // for state restoration even when the url stays the same.
    if (!isRoot) {
      root.notifyListeners();
    }
  }

  /// Builds a simplified hierarchy of current stacks
  ///
  /// This is meant to be used in testing to verify
  /// current hierarchy
  ///
  /// e.g
  ///     expect(router.currentHierarchy(),[
  ///       HierarchySegment(name: HomeRoute.name, children:[
  ///          HierarchySegment(Tab1Route.name),
  ///         ]),
  ///      ]
  ///  );
  List<HierarchySegment> currentHierarchy({
    bool asPath = false,
    bool ignorePending = false,
    bool ignoreParams = false,
  }) => _getCurrentHierarchy(
    stackData,
    asPath: asPath,
    ignoreParams: ignoreParams,
    ignorePending: ignorePending,
  );

  List<HierarchySegment> _getCurrentHierarchy(
    List<RouteData<Object?>> pages, {
    required bool asPath,
    required bool ignorePending,
    required bool ignoreParams,
  }) {
    final hierarchy = <HierarchySegment>[];
    for (final data in pages) {
      final segmentName = asPath ? data.match : data.name;
      final childCtrl = _innerControllerOfPage(data);
      final childSegments = <HierarchySegment>[];
      if (childCtrl?.hasEntries == true) {
        // The child router looks up its own nested routers.
        childSegments.addAll(
          childCtrl!._getCurrentHierarchy(
            childCtrl.stackData,
            asPath: asPath,
            ignorePending: ignorePending,
            ignoreParams: ignoreParams,
          ),
        );
      } else if (!ignorePending && data.hasPendingChildren) {
        childSegments.addAll(
          _getCurrentHierarchy(
            [
              for (final pendingRoute in data.pendingChildren)
                RouteData(
                  stackKey: _stackKey,
                  route: pendingRoute,
                  router: data.router,
                  pendingChildren: [...?pendingRoute.children],
                  type: data.type,
                ),
            ],
            asPath: asPath,
            ignorePending: ignorePending,
            ignoreParams: ignoreParams,
          ),
        );
      }
      hierarchy.add(
        HierarchySegment(
          segmentName,
          children: childSegments,
          pathParams: ignoreParams || data.params.isEmpty ? null : data.params,
          queryParams: ignoreParams || data.queryParams.isEmpty
              ? null
              : data.queryParams,
        ),
      );
    }
    return hierarchy;
  }

  /// Returns an unmodifiable lis of current pages stack data
  List<RouteData<Object?>> get stackData =>
      .unmodifiable(_pages.map((e) => e.routeData));

  /// See [NavigationHistory.isRouteActive]
  bool isRouteActive(String routeName) {
    return navigationHistory.isRouteActive(routeName);
  }

  /// See [NavigationHistory.isRouteDataActive]
  bool isRouteDataActive(RouteData<Object?> data) {
    return navigationHistory.isRouteDataActive(data);
  }

  /// See [NavigationHistory.isPathActive]
  bool isPathActive(String path) {
    return navigationHistory.isPathActive(path);
  }

  Future<List<ReevaluatableRouteMatch<Object?, Object?>>>
  _composeMatchesForReevaluate();

  late Key _stackKey = UniqueKey();

  RouteData<T?> _createRouteData<T>(
    RouteMatch<Object?> route,
    RouteData<Object?> parent, {
    Completer<T?>? popCompleter,
  }) {
    final created = RouteData<T>(
      popCompleter: popCompleter,
      route: route,
      router: this,
      parent: parent,
      stackKey: _stackKey,
      pendingChildren: route.children ?? [],
      type: route.type ?? root.defaultRouteType,
    );
    final takenRestorationIds = {
      for (final page in _pages)
        if (page.routeData.matchId != created.matchId) page.restorationId,
    };
    created._takeRestorationIdApartFrom(takenRestorationIds);
    for (final ctr in _childControllers) {
      if (ctr._isMarkedForDataUpdate && ctr.key == created.key) {
        ctr
          ..updateRouteData(created)
          .._isMarkedForDataUpdate = false;
      }
    }

    return created;
  }

  /// Helper to find route match
  /// See [RouteMatcher.matchByRoute]
  RouteMatch<Object?>? match(PageRouteInfo route) {
    return matcher.matchByRoute(route);
  }

  // Reports a route no route matches to [onFailure]; without one, throws it,
  // or with [shouldThrow] false returns null.
  RouteMatch<Object?>? _matchOrReportFailure(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
    bool shouldThrow = true,
  }) {
    var match = matcher.matchByRoute(route);
    if (match != null) {
      return match;
    }
    match = matcher.buildPathTo(route);
    if (match == null) {
      final failure = _notFound(route.routeName);
      if (onFailure != null) {
        onFailure(failure);
        return null;
      }
      if (!shouldThrow) return null;
      throw FlutterError(failure.toString());
    }
    return _reuseOpenAncestors(match);
  }

  // [RouteMatcher.buildPathTo] makes up the ancestors of a route nested deeper
  // than this router, with no path params or args. Where the same ancestor is
  // already open, or about to open, take its params and args, so navigating
  // to the route keeps the parent that holds the path params it inherits.
  RouteMatch<Object?> _reuseOpenAncestors(RouteMatch<Object?> built) {
    final chain = built.flattened;
    RoutingController? controller = this;
    var pending = const <RouteMatch<Object?>>[];
    for (var i = 0; i < chain.length - 1; i++) {
      final link = chain.elementAtOrNull(i);
      if (link == null) break;
      final name = link.name;
      RouteMatch<Object?>? open;
      if (controller != null) {
        final data = controller.stackData.lastWhereOrNull(
          (d) => d.name == name,
        );
        open = data?.route;
        if (data != null) {
          // A nested router that isn't built yet holds its routes as pending
          // children.
          pending = data.pendingChildren;
          controller = controller._innerControllerOfMatch(data.matchId);
        }
      } else {
        open = pending.lastWhereOrNull((m) => m.name == name);
        pending = open?.children ?? const [];
      }
      if (open == null) break;
      chain[i] = link.copyWith(
        stringMatch: open.stringMatch,
        segments: open.segments,
        params: open.params,
        args: open.args,
        key: open.key,
      );
    }
    return UrlState.toHierarchy(chain);
  }

  List<RouteMatch<Object?>>? _matchAllOrReportFailure(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool shouldThrow = true,
  }) {
    final matches = <RouteMatch<Object?>>[];
    for (final route in routes) {
      final match = _matchOrReportFailure(
        route,
        onFailure: onFailure,
        shouldThrow: shouldThrow,
      );
      if (match != null) {
        // Only a stack opens listed routes one above the other; a tabs router
        // shows each listed route as its own tab.
        final previous = matches.lastOrNull;
        final merged = this is StackRouter && previous != null
            ? _mergeIntoParent(previous, match)
            : null;
        if (merged != null) {
          matches
            ..removeLast()
            ..add(merged);
        } else {
          matches.add(match);
        }
      } else {
        return null;
      }
    }
    return matches;
  }

  // A route of a nested router that isn't open comes inside the parents made
  // up for it. When [next]'s made-up parent is the route [previous] opens, its
  // children join [previous]'s, so routes listed together open in one nested
  // router instead of each in its own copy of the parent.
  RouteMatch<Object?>? _mergeIntoParent(
    RouteMatch<Object?> previous,
    RouteMatch<Object?> next,
  ) {
    if (!next.autoFilled || next.name != previous.name) return null;
    final children = [...?previous.children];
    for (final child in next.children ?? const <RouteMatch<Object?>>[]) {
      final last = children.lastOrNull;
      final merged = last == null ? null : _mergeIntoParent(last, child);
      if (merged != null) {
        children
          ..removeLast()
          ..add(merged);
      } else {
        children.add(child);
      }
    }
    return previous.copyWith(children: children);
  }

  /// Whether is router is used by a declarative-routing widget
  bool get managedByWidget;

  bool _canHandleNavigation(PageRouteInfo route) {
    return routeCollection.containsKey(route.routeName);
  }

  _RouterScopeResult<T>?
  _findPathScopeOrReportFailure<T extends RoutingController>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    if (path.startsWith('/')) {
      final scope = root._absolutePathScope(
        path,
        includePrefixMatches: includePrefixMatches,
      );
      if (scope != null && scope.router is T) {
        return _RouterScopeResult(scope.router as T, scope.matches);
      }
    }
    final routers = _topMostRouter(ignorePagelessRoutes: true)
        ._buildRoutersHierarchy()
        .whereType<T>();

    for (final router in routers) {
      final matches = router.matcher.match(
        path,
        includePrefixMatches: includePrefixMatches,
      );
      if (matches != null) {
        return _RouterScopeResult(router, matches);
      }
    }
    final failure = _notFound(path);
    if (onFailure != null) {
      onFailure(failure);
    } else {
      throw FlutterError(failure.toString());
    }
    return null;
  }

  // Reports [target], with the app's routes, so the message shows the paths
  // that exist next to the one that matched nothing.
  RouteNotFoundFailure _notFound(String target) =>
      .new(target, routeTree: root.routeCollection.toTreeString());

  // Matches an absolute path from this router, the root, the way a deep link
  // is matched: a nested router's relative paths never see the leading '/',
  // so only its wild-card would take it. Then follows the open stack routers
  // whose top page is the next match, and returns the deepest of them with
  // the matches left for it.
  _RouterScopeResult<RoutingController>? _absolutePathScope(
    String path, {
    required bool includePrefixMatches,
  }) {
    final found = matcher.match(
      path,
      includePrefixMatches: includePrefixMatches,
    );
    if (found == null) return null;
    var matches = found;
    var router = this;
    // While a single match with children is left, its children go on in the
    // nested router that already shows it.
    while (true) {
      final match = matches.singleOrNull;
      final children = match?.children;
      if (match == null || children == null || children.isEmpty) break;
      final top = router.stackData.lastOrNull;
      if (top == null ||
          top.name != match.name ||
          top.match != match.stringMatch) {
        break;
      }
      final child = router._topInnerControllerOf(top.key);
      if (child is! StackRouter) break;
      router = child;
      matches = children;
    }
    return _RouterScopeResult(router, matches);
  }

  RoutingController _findScope(PageRouteInfo route) {
    return _topMostRouter(ignorePagelessRoutes: true)
        ._buildRoutersHierarchy()
        .firstWhere((r) => r._canHandleNavigation(route), orElse: () => this);
  }

  /// Pops until given [route], if it already exists in stack otherwise adds it
  /// to the stack (good for web Apps and to avoid duplicate entries).
  ///
  /// The pages above it leave only once the guards of [route] let it through;
  /// a rejected [route] leaves the stack as it was.
  ///
  /// A [route] that is open and holds a nested router sends that router to
  /// the children it is given, or to its initial child. Given no children and
  /// with no initial child, it says nothing about the pages inside, so the
  /// nested router keeps the pages it shows. [navigatePath], a link and
  /// [back] name the whole state: with no page named for a nested router,
  /// they empty it.
  ///
  /// When no guard makes [route] or its children wait, the nested router or
  /// the tabs of the page it reaches show those children as this call
  /// returns, as its own stack holds its page then, see [StackRouter.push]:
  /// a call made right after it on that nested router or those tabs acts on
  /// them as they then are. The same holds for [navigatePath] and
  /// [StackRouter.replaceAll]. The nested router of a page that is new is
  /// built with the page, and opens its children then.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  Future<T?> navigate<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    return await _findScope(route)._navigate(route, onFailure: onFailure);
  }

  /// Pops until given [path], if it already exists in stack
  /// otherwise adds it to the stack
  ///
  /// The pages above it leave only once the guards of its route let it
  /// through; a rejected route leaves the stack as it was.
  ///
  /// A [path] names the whole state, as a url does: a nested router of the
  /// page it reaches that [path] names no page for, and whose route has no
  /// initial child, is emptied. See [navigate] to keep its pages.
  ///
  /// An absolute [path] into the nested router of a page already open goes
  /// straight to that router: the dialogs over that page stay open, and the
  /// app closes them itself, as a dialog's button that navigates and then
  /// pops its dialog does. [navigate] closes them once the guards of that
  /// router let the navigation in.
  ///
  /// if [includePrefixMatches] is true prefixed-matches
  /// will be added to to target destination
  /// see [RouteMatcher.matchUri]
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown. A guard's rejection reaches it as a
  /// [RejectedByGuardFailure].
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findPathScopeOrReportFailure<RoutingController>(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
    if (scope != null) {
      return scope.router._navigateAll(scope.matches, onFailure: onFailure);
    }
    return SynchronousFuture(null);
  }

  Future<T?> _navigate<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    final match = _matchOrReportFailure(route, onFailure: onFailure);
    if (match != null) {
      return await _navigateAll(
        [match],
        onFailure: onFailure,
        keepsUnnamedPages: true,
      );
    }
    return null;
  }

  List<RoutingController> _buildRoutersHierarchy() {
    void collectRouters(
      RoutingController currentParent,
      List<RoutingController> all,
    ) {
      all.add(currentParent);
      if (currentParent._parent != null) {
        collectRouters(currentParent._parent!, all);
      }
    }

    final routers = [this];
    if (_parent != null) {
      collectRouters(_parent!, routers);
    }
    return routers;
  }

  // should find a way to avoid this
  void _updateSharedPathData({
    Map<String, Object?> queryParams = const {},
    String fragment = '',
    bool includeAncestors = false,
  });

  /// Takes a state snapshot of the current segments
  int get stateHash =>
      const ListEquality<Object?>().hash(_addedSegments) ^ pageCount;

  /// The Identifier key of this routing controller
  Key get key;

  /// The unique identifier of the [RouteMatch] linked to this controller
  Key get matchId;

  /// The matcher used by this controller
  /// see [RouteMatcher]
  RouteMatcher get matcher;

  /// The current pages stack of this controller
  List<AutoRoutePage<Object?>> get stack;

  RoutingController? get _parent;

  /// Whether this controller has the top-most visible page of the whole
  /// router tree, not only of its own subtree.
  bool get isTopMost => this == topMostRouter();

  /// Whether every tabs router above this controller shows the tab that
  /// holds it.
  ///
  /// The router of a tab that isn't active stays mounted but hidden, and
  /// back must not reach it.
  @internal
  bool get isInActiveTabs {
    var child = this;
    for (var parent = _parent; parent != null; parent = parent._parent) {
      if (parent is TabsRouter && parent.currentChild?.key != child.key) {
        return false;
      }
      child = parent;
    }
    return true;
  }

  /// The tabs routers above this controller, nearest first.
  @internal
  List<TabsRouter> get ancestorTabsRouters => [
    for (var parent = _parent; parent != null; parent = parent._parent)
      if (parent is TabsRouter) parent,
  ];

  /// The parent controller when it is a [T], otherwise null.
  ///
  /// The root router has no parent. The router of a tab has a [TabsRouter]
  /// for parent, so `parent<StackRouter>()` answers null there, and
  /// `parent<TabsRouter>()` answers null for a router nested in a page of a
  /// [StackRouter].
  T? parent<T extends RoutingController>() {
    final parent = _parent;
    return parent is T ? parent : null;
  }

  /// See [NavigationHistory.canNavigateBack]
  bool get canNavigateBack => navigationHistory.canNavigateBack;

  /// See [NavigationHistory.back]
  void back() => navigationHistory.back();

  /// See [NavigationHistory.pushPathState]
  void pushPathState(Object? state) => navigationHistory.pushPathState(state);

  /// See [NavigationHistory.pathState]
  Object? get pathState => navigationHistory.pathState;

  /// Returns the root router as [RootStackRouter]
  RootStackRouter get root => (_parent?.root ?? this) as RootStackRouter;

  /// Completes once the pages of every router in the app have ended their
  /// transitions: a page coming in after a push or replace, and a page
  /// leaving after a pop.
  ///
  /// Call it right after the navigation, without awaiting the navigation's
  /// own future: the future of [StackRouter.push] completes only when the
  /// pushed page is popped. For example, to open a bottom sheet once the page
  /// has come in, since a sheet opened while the page still moves can close
  /// at once:
  ///
  /// ```dart
  /// unawaited(context.router.push(const DetailsRoute()));
  /// await context.router.waitForTransitions();
  /// if (context.mounted) showModalBottomSheet(context: context, builder: ...);
  /// ```
  ///
  /// It checks after every frame, from the frame after the call, so a page
  /// pushed just before the call has started to come in. A push still
  /// waiting on an asynchronous guard is not waited for, and neither are
  /// dialogs and other routes pushed without a page. With nothing moving, it
  /// completes after the next frame.
  Future<void> waitForTransitions() async {
    do {
      await SchedulerBinding.instance.endOfFrame;
    } while (_hasTransitionIn(root));
  }

  // Whether a page of [router], or of a router nested in it, is coming in or
  // leaving, or a push to it is about to add its page.
  static bool _hasTransitionIn(RoutingController router) {
    if (router case final StackRouter stack) {
      stack._leavingAnimations.removeWhere(
        (animation) => !animation.isAnimating,
      );
      if (stack._landingPushes.isNotEmpty ||
          stack._leavingAnimations.isNotEmpty) {
        return true;
      }
      if (stack._pages.any(
        (page) => page.routeData.animation?.isAnimating ?? false,
      )) {
        return true;
      }
    }
    return router._childControllers.any(_hasTransitionIn);
  }

  /// The parent controller when it is a [StackRouter], otherwise null, as for
  /// the root router and for the router of a tab; see [parent].
  StackRouter? get parentAsStackRouter => parent();

  /// Whether is controller is the root of all controllers
  bool get isRoot => _parent == null;

  RoutingController _topMostRouter({bool ignorePagelessRoutes = false});

  /// Finds the router with top-most visible page
  ///
  /// if [ignorePagelessRoutes] is true pageless routes
  /// will be ignored
  ///
  /// What is a (PagelessRoute)?
  /// [Route] that does not correspond to a [Page] object is called a pageless
  /// route and is tied to the [Route] that _does_ correspond to a [Page] object
  /// that is below it in the history.
  RoutingController topMostRouter({bool ignorePagelessRoutes = false}) {
    return root._topMostRouter(ignorePagelessRoutes: ignorePagelessRoutes);
  }

  /// The active child representation of an implementation of this controller
  ///
  /// e.g it could be the top-most route of a [StackRouter] or
  /// the child corresponding with activeIndex in [TabsRouter]
  RouteData<Object?>? get currentChild;

  /// Returns [currentChild] if it's rendered
  /// otherwise returns parent [routeData]
  RouteData<Object?> get current;

  /// The top-most rendered route
  RouteData<Object?> get topRoute => _topMostRouter().current;

  /// The top-most rendered or pending route match
  RouteMatch<Object?> get topMatch => topRoute.topMatch;

  /// The data of the parent route
  RouteData<Object?> get routeData;

  /// Updates the value of [routeData]
  void updateRouteData(RouteData<Object?> data);

  /// The list of routes consumed by this controller
  RouteCollection get routeCollection;

  /// The top-most visible page
  AutoRoutePage<Object?>? get topPage => _topMostRouter()._pages.lastOrNull;

  /// Whether this controller has rendered pages
  bool get hasEntries => _pages.isNotEmpty;

  /// The count of rendered pages
  int get pageCount => _pages.length;

  /// Finds a child route corresponding to [routeName]
  /// and casts it to [T]
  ///
  /// returns null if it does not find it
  T? innerRouterOf<T extends RoutingController>(String routeName) {
    if (_childControllers.isEmpty) {
      return null;
    }
    return _childControllers.whereType<T>().lastWhereOrNull(
      (c) => c.routeData.name == routeName,
    );
  }

  /// Clients can either pop their own [_pages] stack
  /// or defer the call to a parent controller
  ///
  /// see [Navigator.maybePop(context)] for more details
  @optionalTypeArgs
  Future<bool> maybePop<T extends Object?>([T? result]);

  /// Calls [maybePop] on the controller with the top-most visible page
  @optionalTypeArgs
  Future<bool> maybePopTop<T extends Object?>([T? result]) =>
      _topMostRouter().maybePop(result);

  /// Clients can either pop their own [_pages] stack
  /// or defer the call to a parent controller
  ///
  /// see [Navigator.pop(context)] for more details
  @optionalTypeArgs
  void pop<T extends Object?>([T? result]);

  /// Calls [pop] on the controller with the top-most visible page
  @optionalTypeArgs
  void popTop<T extends Object?>([T? result]) => _topMostRouter().pop(result);

  /// Whether this controller can preform [maybePop]
  ///
  /// if [ignoreChildRoutes] is true
  /// it will only check whether this controller has multiple entire
  /// and not care about pop-able child controllers
  ///
  /// if [ignoreParentRoutes] is true
  /// it will only check whether this controller has multiple entire
  /// and not care about pop-able parent controllers
  ///
  /// if [ignorePagelessRoutes] is true
  /// page-lss routes will not be considered in the calculation
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  });

  /// returns true if any child controller can pop
  bool childrenCanPop({bool ignorePagelessRoutes = false}) {
    return _childControllers.any(
      (c) => c.canPop(
        ignorePagelessRoutes: ignorePagelessRoutes,
        ignoreParentRoutes: true,
      ),
    );
  }

  /// returns true if the active child controller can pop
  bool activeRouterCanPop({bool ignorePagelessRoutes = false}) {
    final innerRouter = _innerControllerOfPage(currentChild);
    if (innerRouter != null) {
      return innerRouter.canPop(
        ignorePagelessRoutes: ignorePagelessRoutes,
        ignoreParentRoutes: true,
      );
    }
    return false;
  }

  /// Collects the top-most visitable current-child of
  /// every top-most nested controller considering this controller as root
  List<RouteMatch<Object?>> get currentSegments {
    final currentData = currentChild;
    final segments = <RouteMatch<Object?>>[];
    if (currentData != null) {
      segments.add(currentData.route);
      final childCtrl = _innerControllerOfPage(currentData);
      if (childCtrl?.hasEntries == true) {
        segments.addAll(childCtrl!.currentSegments);
      } else if (currentData.pendingChildren case [..., final last]) {
        segments.addAll(last.flattened);
      }
    }
    return segments;
  }

  /// this is an indicator for controller state changes, every controller's
  /// state is considered updated if it's stateHash or any of it's children's
  /// stateHash changes
  List<RouteMatch<Object?>> get _addedSegments {
    final currentData = currentChild;
    final segments = <RouteMatch<Object?>>[];
    if (currentData != null) {
      segments.add(currentData.route);
      final childCtrl = _innerControllerOfPage(currentData);
      if (childCtrl?.hasEntries == true) {
        segments.addAll(childCtrl!._addedSegments);
      }
    }
    return segments;
  }

  /// Finds match of [path] then returns a route-able entity
  PageRouteInfo? buildPageRoute(
    String? path, {
    bool includePrefixMatches = true,
  }) {
    if (path == null) return null;
    return matcher
        .match(path, includePrefixMatches: includePrefixMatches)
        ?.firstOrNull
        ?.toPageRouteInfo();
  }

  /// Finds matches of [path] then returns a list of route-able entities
  List<PageRouteInfo>? buildPageRoutesStack(
    String? path, {
    bool includePrefixMatches = true,
  }) {
    if (path == null) return null;
    return matcher
        .match(path, includePrefixMatches: includePrefixMatches)
        ?.map((m) => m.toPageRouteInfo())
        .toList();
  }

  @override
  String toString() => '${routeData.name} Router';

  // With [keepsUnnamedPages], a nested router that [routes] reach and name
  // no pages for keeps the pages it shows, as navigate to a route object
  // asks: a route given no children says nothing about them. A path, a link
  // and a history entry name the whole state, so without it such a router is
  // emptied.
  //
  // [link] is the count of the link whose navigation this is, handed down by
  // the batch of the router above; without it, the link whose navigation
  // the delegate is starting in this call, if any.
  //
  // [onLetIn] is what the router above does once this router, and the
  // nested router of the page or tab it reaches, have let the navigation in,
  // such as closing the dialogs over its page; a rejection drops it.
  //
  // [onGuardShowsPage] is told with the router each time a guard of this
  // navigation puts a page of its own on a stack while it decides, such as
  // a sign-in page, so a tab that waits for these guards can show it.
  Future<T?> _navigateAll<T extends Object?>(
    List<RouteMatch<Object?>> routes, {
    OnNavigationFailure? onFailure,
    bool isReevaluating = false,
    bool keepsUnnamedPages = false,
    int? link,
    VoidCallback? onLetIn,
    ValueChanged<StackRouter>? onGuardShowsPage,
  });

  Future<void> _navigateAllRoutes(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
  }) {
    final matches = _matchAllOrReportFailure(routes, onFailure: onFailure);
    if (matches != null) {
      return _navigateAll(matches, onFailure: onFailure);
    }
    return SynchronousFuture(null);
  }
}

/// An implementation of a [RoutingController] that handles parallel routeing
///
/// aka Tab-Routing
class TabsRouter extends RoutingController {
  /// Default constructor
  new({
    required RouteCollection routeCollection,
    required this.key,
    required this._routeData,
    required this.preload,
    required this.matchId,
    this._homeIndex = -1,
    this._backThroughHistory = false,
    this._parent,
  }) : _routeCollection = routeCollection,
       _matcher = RouteMatcher(routeCollection);
  @override
  final RoutingController? _parent;
  @override
  final Key key;
  @override
  final Key matchId;
  RouteCollection _routeCollection;
  RouteMatcher _matcher;

  @override
  RouteCollection get routeCollection => _routeCollection;

  @override
  RouteMatcher get matcher => _matcher;

  @override
  void _reassemble() {
    if (_parent?._reassembledSubCollection(_routeData.name)
        case final collection?) {
      _routeCollection = collection;
      _matcher = RouteMatcher(collection);
    }
    super._reassemble();
  }

  // A child route of this router's parent route that is not one of the tabs,
  // such as a tab the app removed from its list, has no place here. The
  // navigation is turned down, as a guard's "no" turns one down: the tab on
  // screen, its url and the dialogs over it stay, and a link counts as
  // turned down, so the url goes back to the page on screen. The caller
  // hears of it, as of any route no router can show: [onFailure] gets a
  // [RouteNotFoundFailure], and without it the app's own call throws. A link
  // has no caller to throw to.
  //
  // UITabBarController can select only a view controller in its
  // viewControllers array, and an app that can't open a link returns false
  // from application(_:open:options:) and keeps what it shows. Android's
  // NavController.handleDeepLink returns false for a destination its graph
  // lacks, and nothing changes.
  void _turnDownRouteNotListed(
    RouteMatch<Object?> route, {
    required int? link,
    OnNavigationFailure? onFailure,
  }) {
    // The link's step is never taken: the link is not let in.
    if (link != null) root._takeLinkStep(link);
    if (onFailure != null) {
      return onFailure(RouteNotFoundFailure(route.name));
    }
    if (link != null) return;
    throw FlutterError(
      'Can not navigate to ${route.name}: it is not one of the tabs of the '
      'tabs router of ${routeData.name}. Add it to the routes of its '
      'AutoTabsRouter, or show it in a router of its own.',
    );
  }

  RouteData<Object?> _routeData;
  int _activeIndex = 0;
  int? _previousIndex;

  /// The index to pop from
  ///
  /// if activeIndex != homeIndex
  /// set activeIndex to homeIndex
  /// else pop parent
  ///
  /// [AutoTabsRouter] sets it whenever it is rebuilt with another homeIndex.
  /// An index past the end of the tabs counts as no home tab.
  int get homeIndex => _homeIndex;

  /// Makes the tab at [value] the one back goes to, or none when it is -1.
  ///
  /// Android is told after the frame whether the app still takes back, as
  /// this is set while the [AutoTabsRouter] above builds.
  set homeIndex(int value) {
    if (_homeIndex == value) return;
    _homeIndex = value;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!_isDisposed) root.notifyListeners();
      })
      ..ensureVisualUpdate();
  }

  int _homeIndex;

  // The tab back goes to, or -1: the tabs may have become fewer than
  // [homeIndex] counts on.
  int get _homeTab => homeIndex < _pages.length ? homeIndex : -1;

  /// Whether back shows the tabs visited before the active one, the latest
  /// first, before it leaves the tabs.
  ///
  /// Back is [maybePop] and [pop], which Android's back key and the
  /// predictive back gesture reach. While a tab is left to go back to, the
  /// app tells Android it handles back, so Android 13 and later don't close
  /// the app instead. Defaults to false.
  ///
  /// Each tab is in the history once, where it was left last: after tabs 0,
  /// 1, 0 and 2, back shows 0, then 1. A tab whose guards keep it out is
  /// skipped. Once the history is gone through, back goes on as it would
  /// without it: to the [homeIndex] tab when there is one and it isn't
  /// active, else out of the tabs.
  ///
  /// The history lives as long as this router and is not restored with
  /// the app's state. When the tabs change, it keeps the tabs still there.
  ///
  /// [AutoTabsRouter] sets it whenever it is rebuilt with another value.
  bool get backThroughHistory => _backThroughHistory;

  /// Makes back go through the tabs visited before, or not.
  ///
  /// The history is only kept while this is true, so turning it off forgets
  /// it. Android is told after the frame whether the app still takes back,
  /// as this is set while the [AutoTabsRouter] above builds.
  set backThroughHistory(bool value) {
    if (_backThroughHistory == value) return;
    _backThroughHistory = value;
    if (value) return;
    final hadHistory = _tabHistory.isNotEmpty;
    _tabHistory.clear();
    if (!hadHistory) return;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!_isDisposed) root.notifyListeners();
      })
      ..ensureVisualUpdate();
  }

  bool _backThroughHistory;

  // The tabs shown before the active one, the latest last, each once.
  final _tabHistory = <int>[];

  // Whether back stays inside these tabs, by showing another one.
  bool get _doesTakeBack =>
      (backThroughHistory && _tabHistory.isNotEmpty) ||
      (_homeTab != -1 && _activeIndex != _homeTab);

  /// Called to preload a page before other navigation events occur if it
  /// returns true, the page has been preloaded, otherwise we assume it's
  /// already loaded
  bool Function(int index) preload;

  @override
  RouteData<Object?> get routeData => _routeData;

  @override
  void updateRouteData(RouteData<Object?> data) {
    _routeData = data;
    for (final page in _pages) {
      page.routeData._parent = data;
    }
  }

  @override
  RouteData<Object?> get current {
    return currentChild ?? routeData;
  }

  @override
  RouteData<Object?>? get currentChild {
    return _pages.elementAtOrNull(_activeIndex)?.routeData;
  }

  /// The index of active page
  int get activeIndex => _activeIndex;

  /// The index of previous active page
  ///
  /// When the tabs change, it follows that tab to its new index, as
  /// [activeIndex] does, and is null once that tab is gone or is active.
  int? get previousIndex => _previousIndex;

  /// Updates [_activeIndex] and triggers a rebuild
  ///
  /// The tab at [index] shows only once the guards of its route let it in.
  /// When a guard decides later, the current tab stays active until then,
  /// and the change always notifies once it happens.
  void setActiveIndex(int index, {bool notify = true}) {
    assert(
      index >= 0 && index < _pages.length,
      'Tab index $index is out of range for ${_pages.length} tabs.',
    );
    // A change waits on the tab's guards when it has any; nothing here waits
    // for it.
    if (_changeTab(index, notify: notify) case final Future<void> change) {
      unawaited(change);
    }
  }

  // The latest change of the active tab, and the tab of one whose guards are
  // still deciding, with whether it happens.
  int _tabChanges = 0;
  int? _pendingTab;
  Future<_TabChange>? _pendingChange;

  // Every change of the active tab goes through here: setActiveIndex, which
  // the tabs views call too, back to a tab, and navigating to a tab. A change
  // that is not [remember]ed, such as one made by back, adds nothing to the
  // tab history.
  //
  // The tab shows once the guards of its route let it in. [route] is the
  // route a navigation opens the tab with; the tab's page is then updated
  // with it, and its nested router navigates to its children. Answers how
  // the change ended: at once when every guard answers at once, otherwise
  // once they have. A change to another tab made meanwhile replaces one
  // still waiting for its guards.
  FutureOr<_TabChange> _changeTab(
    int index, {
    bool notify = true,
    RouteMatch<Object?>? route,
    OnNavigationFailure? onFailure,
    bool remember = true,
    bool keepsUnnamedPages = false,
    int? link,
    VoidCallback? onLetIn,
  }) {
    if (_activeIndex == index) {
      onLetIn?.call();
      return _TabChange.done;
    }
    // A view asks again for the tab it moved to while its guards decide.
    if (route == null && _pendingTab == index) return _pendingChange!;
    final match = route ?? _pages.elementAtOrNull(index)?.routeData._route;
    if (match == null) {
      onLetIn?.call();
      return _TabChange.done;
    }
    final change = ++_tabChanges;
    // What a link that changes the tab does once the tab's guards let it in.
    final onLinkAccepted = link == null ? null : root._takeLinkStep(link);
    final checked = _checkTabGuards(
      match,
      onFailure: onFailure,
      change: change,
    );
    if (checked is ResolverResult) {
      return _endTabChange(
        change,
        index,
        match,
        checked,
        onLinkAccepted: onLinkAccepted,
        link: link,
        onLetIn: onLetIn,
        notify: notify,
        update: route != null,
        onFailure: onFailure,
        remember: remember,
        keepsUnnamedPages: keepsUnnamedPages,
      );
    }
    _pendingTab = index;
    final pending = _pendingChange = checked.then(
      (result) => _endTabChange(
        change,
        // The tabs may have changed meanwhile: replaceAll moves the tab.
        _pendingTab ?? index,
        match,
        result,
        onLinkAccepted: onLinkAccepted,
        link: link,
        onLetIn: onLetIn,
        update: route != null,
        onFailure: onFailure,
        remember: remember,
        keepsUnnamedPages: keepsUnnamedPages,
      ),
      onError: (Object error, StackTrace stackTrace) =>
          _failTabChange(change, error, stackTrace),
    );
    // A view that moved to the tab, e.g. a page view swiped to it, shows the
    // active one until the guards let the tab in. Told once the change is
    // set, so a listener that asks for the tab again gets this change.
    if (notify) notifyListeners();
    return pending;
  }

  // Ends the change [change] whose guard threw: the tab stays out, the next
  // change to it asks its guards anew, and the error goes on to the caller.
  Never _failTabChange(int change, Object error, StackTrace stackTrace) {
    if (!_isDisposed && change == _tabChanges) {
      _pendingTab = null;
      _pendingChange = null;
      // A view that moved to the tab goes back to the active one.
      notifyListeners();
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  // Calls off the change of the active tab still waiting for its guards: it
  // ends as replaced once they answer.
  void _callOffPendingChange() {
    _tabChanges++;
    _pendingTab = null;
    _pendingChange = null;
  }

  _TabChange _endTabChange(
    int change,
    int index,
    RouteMatch<Object?> match,
    ResolverResult result, {
    VoidCallback? onLinkAccepted,
    int? link,
    VoidCallback? onLetIn,
    bool notify = true,
    bool update = false,
    OnNavigationFailure? onFailure,
    bool remember = true,
    bool keepsUnnamedPages = false,
  }) {
    if (_isDisposed || change != _tabChanges) return .replaced;
    _pendingTab = null;
    _pendingChange = null;
    if (!result.continueNavigation) {
      // A view that moved to the tab goes back to the active one.
      if (notify) notifyListeners();
      return .rejected;
    }
    final isUpdated = update || !identical(result.route, match);
    // A link that goes on to pages in the tab's nested router shows the tab
    // once the guards there let it in, as a link into the nested router of a
    // page already open does: one they reject leaves the tab on screen and
    // the open dialogs as they were.
    if (onLinkAccepted != null &&
        link != null &&
        isUpdated &&
        (result.route.children ?? const []).isNotEmpty) {
      _showTabOnceLinkLetIn(
        change,
        index,
        result.route,
        link: link,
        onLinkAccepted: onLinkAccepted,
        show: () => _showTab(index, notify: notify, remember: remember),
        then: onLetIn,
        onFailure: onFailure,
      );
      return .done;
    }
    // The app's own change to a tab whose nested router is built, to pages
    // in that router, shows the tab once the guards there let it in, as a
    // link's change does: one they reject leaves the tab on screen and the
    // open dialogs as they were. Or before, when one of them shows a page of
    // its own in the tab while it decides. A tab whose nested router isn't
    // built yet is built off the screen first, as a link's is, when a guard
    // is to be asked there; with none to ask, it shows in the call.
    final tabMatchId = _pages.elementAtOrNull(index)?.routeData.matchId;
    final tabRouter = tabMatchId == null
        ? null
        : _innerControllerOfMatch(tabMatchId);
    final goesInside =
        onLinkAccepted == null &&
        isUpdated &&
        (result.route.children ?? const []).isNotEmpty;
    if (goesInside &&
        tabRouter == null &&
        _asksGuards(result.route.children ?? const [])) {
      _showTabOnceLinkLetIn(
        change,
        index,
        result.route,
        show: () => _showTab(index, notify: notify, remember: remember),
        then: onLetIn,
        onFailure: onFailure,
        keepsUnnamedPages: keepsUnnamedPages,
      );
      return .done;
    }
    if (goesInside && tabRouter != null) {
      final updated = _updateTabPage(
        index,
        result.route,
        keepsUnnamedPages: keepsUnnamedPages,
      );
      final show = _showingTabOnce(
        change,
        () => _showTab(index, notify: notify, remember: remember),
      );
      unawaited(
        _navigateInsideTab(
          updated,
          onFailure: onFailure,
          keepsUnnamedPages: keepsUnnamedPages,
          link: link,
          onLetIn: () {
            show();
            onLetIn?.call();
          },
          onGuardShowsPage: (router) {
            if (_isInside(router, tabRouter)) show();
          },
        ),
      );
      return .done;
    }
    onLinkAccepted?.call();
    // A guard may have overridden the route, e.g. its args.
    final updated = isUpdated
        ? _updateTabPage(
            index,
            result.route,
            keepsUnnamedPages: keepsUnnamedPages,
          )
        : null;
    _showTab(index, notify: notify, remember: remember);
    if (updated == null) {
      onLetIn?.call();
    } else {
      unawaited(
        _navigateInsideTab(
          updated,
          onFailure: onFailure,
          keepsUnnamedPages: keepsUnnamedPages,
          link: link,
          onLetIn: onLetIn,
        ),
      );
    }
    return .done;
  }

  // Makes the tab at [index] the active one.
  void _showTab(int index, {required bool notify, required bool remember}) {
    // Preloads while the old tab is still active, whether or not this notifies.
    final shouldWaitForFrame =
        preload(index) &&
        notify &&
        SchedulerBinding.instance.schedulerPhase != .idle;
    if (backThroughHistory) {
      _tabHistory
        ..remove(index)
        ..remove(_activeIndex);
      if (remember) _tabHistory.add(_activeIndex);
    }
    _previousIndex = _activeIndex;
    _activeIndex = index;
    if (shouldWaitForFrame) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        // The tabs may be disposed by the end of the frame.
        if (!_isDisposed) notifyAll();
      });
    } else if (notify) {
      notifyAll();
    }
  }

  // [show], once, for the change [change]: not once a later change replaced
  // it or the tabs are disposed. The tab shows when the guards of its nested
  // router let the navigation in, or before, when one of them puts a page of
  // its own in the tab while it decides, such as a sign-in page the user has
  // to see to answer it.
  VoidCallback _showingTabOnce(int change, VoidCallback show) {
    var isShown = false;
    return () {
      if (isShown || _isDisposed || change != _tabChanges) return;
      isShown = true;
      show();
    };
  }

  // Whether [router] is [outer] or a router nested inside it.
  static bool _isInside(RoutingController router, RoutingController outer) {
    for (RoutingController? at = router; at != null; at = at._parent) {
      if (identical(at, outer)) return true;
    }
    return false;
  }

  // Whether opening [routes], and the routes they name for the nested
  // routers of their pages, asks a guard: one of their own, or one of the
  // app's global guards, which every stack asks.
  bool _asksGuards(List<RouteMatch<Object?>> routes) =>
      root.guards.isNotEmpty ||
      routes.any(
        (route) =>
            route.guards.isNotEmpty || _asksGuards(route.children ?? const []),
      );

  // Opens the pages [route] names in the nested router of the tab at
  // [index], and runs [show], [onLinkAccepted] and [then] once their guards
  // let the navigation in, unless the change [change] was replaced
  // meanwhile. A navigation of a [link] hands those steps to the link's
  // step; the app's own runs them as the nested router lets it in. A tab
  // whose nested router is not built yet is built offstage first, on its
  // first page, as preload builds it, so the guards are asked with the tab
  // the user is on still on screen.
  void _showTabOnceLinkLetIn(
    int change,
    int index,
    RouteMatch<Object?> route, {
    required VoidCallback show,
    int? link,
    VoidCallback? onLinkAccepted,
    VoidCallback? then,
    OnNavigationFailure? onFailure,
    bool keepsUnnamedPages = false,
  }) {
    final showOnce = _showingTabOnce(change, show);
    void onLetIn() {
      showOnce();
      onLinkAccepted?.call();
      then?.call();
    }

    void openInside(RouteMatch<Object?> tab) {
      if (link != null) root._handLinkStepOn(link, onLetIn);
      final tabRouter = _innerControllerOfMatch(tab.id);
      unawaited(
        _navigateInsideTab(
          tab,
          onFailure: onFailure,
          keepsUnnamedPages: keepsUnnamedPages,
          link: link,
          onLetIn: link == null ? onLetIn : null,
          onGuardShowsPage: (router) {
            if (tabRouter != null && _isInside(router, tabRouter)) showOnce();
          },
        ),
      );
      // A nested router whose navigation asks no guard, such as a
      // declarative one, leaves the step: the tab shows at once.
      if (link != null) root._takeLinkStep(link)?.call();
    }

    final tabMatchId = _pages.elementAtOrNull(index)?.routeData.matchId;
    if (tabMatchId != null && _innerControllerOfMatch(tabMatchId) != null) {
      return openInside(
        _updateTabPage(index, route, keepsUnnamedPages: keepsUnnamedPages),
      );
    }
    final children = route.children;
    final firstPage = _updateTabPage(
      index,
      route.copyWith(children: const []),
      keepsUnnamedPages: keepsUnnamedPages,
    );
    if (!preload(index)) {
      // A tab that can't be built offstage shows as before the guards ask.
      onLetIn();
      unawaited(
        _navigateInsideTab(
          firstPage.copyWith(children: children),
          onFailure: onFailure,
          keepsUnnamedPages: keepsUnnamedPages,
          link: link,
        ),
      );
      return;
    }
    unawaited(
      SchedulerBinding.instance.endOfFrame.then((_) {
        if (_isDisposed || change != _tabChanges) return;
        openInside(firstPage.copyWith(children: children));
      }),
    );
  }

  // Asks the guards of the tab [route] opens whether it may show, the way a
  // stack asks before it shows a page. The app's global guards, in
  // RootStackRouter.guards, are for stack routes only. Answers at once when
  // every guard does, so a tab change that no guard delays stays
  // synchronous. Once [change] is replaced by a later change, or the tabs
  // are disposed, no further guard is asked: the change won't happen.
  // [onLetGo] is called when a guard asked again returns without an answer
  // and without a redirect: the tab leaves the screen until it answers, see
  // [_reevaluateActiveTab].
  //
  // A yes from before a change of the state the guards are asked again for
  // is dropped, and the guard is asked once more, [timesLeft] times at most,
  // as [StackRouter._canNavigate] does for a page: a sign-out that lands
  // while a tab's guard awaits a request never shows the tab.
  FutureOr<ResolverResult> _checkTabGuards(
    RouteMatch<Object?> route, {
    required int change,
    OnNavigationFailure? onFailure,
    bool isReevaluating = false,
    int from = 0,
    VoidCallback? onLetGo,
    int timesLeft = _kMaxAsksAgainInARow,
  }) {
    final guards = route.guards;
    final guard = guards.elementAtOrNull(from);
    if (guard == null) {
      return ResolverResult(
        continueNavigation: true,
        reevaluateNext: true,
        route: route,
      );
    }
    final router = _guardRouter;
    final resolver = NavigationResolver(
      router,
      Completer(),
      route,
      isReevaluating: isReevaluating,
    );
    _tabRoutesOfResolvers[resolver] = matcher;
    final entry = GuardEntry(guard, resolver);
    router.activeGuardObserver._add(entry);
    FutureOr<ResolverResult> onResult(ResolverResult result) {
      router.activeGuardObserver._remove(entry);
      final isAskedAgain =
          result.continueNavigation &&
          resolver._isAnswerStale &&
          timesLeft > 0 &&
          !_isDisposed &&
          change == _tabChanges;
      if (isAskedAgain) {
        // The stale answer is dropped whole, with the route it names.
        return _checkTabGuards(
          route,
          change: change,
          onFailure: onFailure,
          isReevaluating: isReevaluating,
          from: from,
          onLetGo: onLetGo,
          timesLeft: timesLeft - 1,
        );
      }
      if (!result.continueNavigation) {
        onFailure?.call(RejectedByGuardFailure(result.route, guard));
        return result;
      }
      if (_isDisposed || change != _tabChanges) return result;
      return _checkTabGuards(
        result.route,
        change: change,
        onFailure: onFailure,
        isReevaluating: isReevaluating,
        from: from + 1,
        onLetGo: onLetGo,
      );
    }

    final checking = resolver._checkGuard(
      guard,
      router,
      onLeftUndecided: onLetGo == null
          ? null
          : ({required isWaitingOnUser}) {
              if (isWaitingOnUser) return false;
              onLetGo();
              return true;
            },
    );
    if (resolver._result case final result?) {
      checking.ignore();
      return onResult(result);
    }
    return checking.then(
      onResult,
      onError: (Object error, StackTrace stackTrace) {
        router.activeGuardObserver._remove(entry);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  // The stack router guards of the tabs get, the nearest one above them.
  StackRouter get _guardRouter {
    for (var parent = _parent; parent != null; parent = parent._parent) {
      if (parent is StackRouter) return parent;
    }
    return root;
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  List<AutoRoutePage<Object?>> get stack => .unmodifiable(_pages);

  AutoRoutePage<Object?>? get _activePage {
    return _pages.elementAtOrNull(_activeIndex);
  }

  @override
  RoutingController _topMostRouter({bool ignorePagelessRoutes = false}) {
    final innerRouter = _innerControllerOfPage(_activePage?.routeData);
    if (innerRouter != null) {
      return innerRouter._topMostRouter(
        ignorePagelessRoutes: ignorePagelessRoutes,
      );
    }
    return this;
  }

  @override
  @optionalTypeArgs
  Future<bool> maybePop<T extends Object?>([T? result]) {
    final hasShownTab = _hasShownTabOnBack();
    if (hasShownTab is bool) {
      return hasShownTab ? SynchronousFuture(true) : _maybePopParent(result);
    }
    return hasShownTab.then(
      (wasShown) => wasShown ? true : _maybePopParent<T>(result),
    );
  }

  Future<bool> _maybePopParent<T extends Object?>(T? result) {
    if (_parent != null) {
      return _parent!.maybePop(result);
    }
    return SynchronousFuture(false);
  }

  @override
  @optionalTypeArgs
  void pop<T extends Object?>([T? result]) {
    void popParentUnless({required bool shown}) {
      if (!shown) _parent?.pop(result);
    }

    final hasShownTab = _hasShownTabOnBack();
    if (hasShownTab is bool) {
      popParentUnless(shown: hasShownTab);
    } else {
      unawaited(
        hasShownTab.then((wasShown) => popParentUnless(shown: wasShown)),
      );
    }
  }

  // Shows the tab back goes to: the latest in the tab history, else the
  // home tab. Answers whether it showed one; false when there is none, or
  // when the guards of the home tab, and of every tab in the history, keep
  // theirs out. Back then goes on as it would from the home tab.
  FutureOr<bool> _hasShownTabOnBack() {
    final isFromHistory = backThroughHistory && _tabHistory.isNotEmpty;
    final FutureOr<_TabChange> change;
    if (isFromHistory) {
      change = _changeTab(_tabHistory.removeLast(), remember: false);
    } else if (_homeTab != -1 && _activeIndex != _homeTab) {
      change = _changeTab(_homeTab, remember: false);
    } else {
      return false;
    }
    FutureOr<bool> hasShownNext(_TabChange outcome) {
      if (outcome != .rejected) return true;
      return isFromHistory ? _hasShownTabOnBack() : false;
    }

    return change is _TabChange
        ? hasShownNext(change)
        : change.then(hasShownNext);
  }

  // The index in [routes], the tabs as listed, of the tab [route] names, or
  // -1: of the tabs of its route, the first with the path it names, such as
  // 'item/2', else the first.
  static int _listedTabOf(
    List<RouteMatch<Object?>> routes,
    RouteMatch<Object?> route,
  ) {
    final sameRoute = [
      for (final (index, listed) in routes.indexed)
        if (listed.key == route.key) (index, listed),
    ];
    final (index, _) =
        sameRoute
            .where((tab) => tab.$2.stringMatch == route.stringMatch)
            .firstOrNull ??
        sameRoute.firstOrNull ??
        (-1, null);
    return index;
  }

  /// Pushes given [routes] to [_pages] stack
  /// after match validation and deciding initial index
  void setupRoutes(List<PageRouteInfo>? routes) {
    final routesToPush = _resolveRoutes(routes);
    _listedTabArgs = [for (final route in routesToPush) route.args];
    _listedTabChildren = [
      for (final route in routesToPush) route.children ?? const [],
    ];
    // Tabs restored after the app was ended each come with their own stack.
    // The last pending one is the active tab.
    final pendingChildren = _routeData.pendingChildren;
    for (final (pendingIndex, pending) in pendingChildren.indexed) {
      final index = _listedTabOf(routesToPush, pending);
      if (index != -1) {
        final withArgs = _withTabArgs(
          pending,
          _listedTabArgs.elementAtOrNull(index),
        );
        pendingChildren[pendingIndex] = withArgs;
        routesToPush[index] = withArgs;
      }
    }
    final outgoing = _routeData.hasPendingChildren
        ? null
        : _outgoingTabsRouter();
    final preMatchedRoute = switch (_routeData.pendingChildren) {
      [..., final last] => last,
      _ => outgoing?._activePage?.routeData.route,
    };
    // The change that shows a guarded tab, if one does.
    final change = ++_tabChanges;
    var guardedIndex = -1;
    Future<ResolverResult>? guarding;
    // The route a navigation named for these tabs, when it is not one of
    // them. A restore names a route for each tab it brings back, and shows
    // the tabs that are left.
    final notListed =
        pendingChildren.length == 1 &&
            preMatchedRoute != null &&
            _listedTabOf(routesToPush, preMatchedRoute) == -1
        ? preMatchedRoute
        : null;
    if (preMatchedRoute != null) {
      final correspondingRouteIndex = _listedTabOf(
        routesToPush,
        preMatchedRoute,
      );
      // A tab named by a url, a navigation or a restore shows once the guards
      // of its route let it in, and the first tab shows meanwhile or instead.
      // The first tab shows without asking its guards: the tabs must show
      // one, so it's kept out by guarding the route that holds the tabs.
      final checked =
          correspondingRouteIndex <= 0 || !_routeData.hasPendingChildren
          ? null
          : _checkTabGuards(preMatchedRoute, change: change);
      if (checked is Future<ResolverResult>) {
        guardedIndex = correspondingRouteIndex;
        guarding = checked;
      } else if (correspondingRouteIndex != -1 &&
          checked?.continueNavigation != false) {
        routesToPush[correspondingRouteIndex] =
            checked?.route ?? preMatchedRoute;
        _previousIndex = _activeIndex;
        _activeIndex = correspondingRouteIndex;
      }
    }

    if (outgoing != null) {
      _tabHistory.addAll(_historyOf(outgoing._tabHistoryNames, routesToPush));
    }
    if (routesToPush.isNotEmpty) {
      _pushAll(routesToPush, isFromDefault: routes == null);
    }
    _routeData.pendingChildren.clear();
    if (notListed != null) _turnDownPendingRoute(notListed);
    if (guarding != null) {
      final index = guardedIndex;
      final match = preMatchedRoute!;
      _pendingTab = index;
      _pendingChange = guarding.then(
        (result) {
          // The tab takes the first one's place in the url. Not once the tabs
          // are gone: the url that follows is another page's, which must not
          // take the place of the page shown before it.
          if (result.continueNavigation &&
              change == _tabChanges &&
              !_isDisposed) {
            markUrlStateForReplace();
          }
          // The tabs may have changed meanwhile: replaceAll moves the tab.
          return _endTabChange(
            change,
            _pendingTab ?? index,
            match,
            result,
            update: true,
          );
        },
        onError: (Object error, StackTrace stackTrace) =>
            _failTabChange(change, error, stackTrace),
      );
    }
    // A host opened by a url that names no tab, such as '/tabs' when no tab is
    // initial, shows its first tab. The url names that tab too, in place of
    // the host's own entry, so going back to that entry shows it. The router
    // is set up while the app builds, so nobody is told of the new url: the
    // web history writes it over the host's entry by itself.
    if (_pages.isNotEmpty &&
        navigationHistory.isRouteDataActive(routeData) &&
        !navigationHistory.isRouteDataActive(current)) {
      navigationHistory.onNewUrlState(
        UrlState.fromSegments(root.currentSegments, shouldReplace: true),
        notify: false,
      );
    }
  }

  // The navigation that put this router's page on named [route] for it, a
  // route that is not one of the tabs: it is turned down, as in
  // [_turnDownRouteNotListed], once the frame that builds the tabs ends,
  // and the first tab shows meanwhile. The page is taken back, so the stack
  // and the url are as before the navigation, unless it is the only page
  // its stack has, as when the app starts at the link: it then stays, on its
  // first tab. Nothing waits when the page went on long before.
  void _turnDownPendingRoute(RouteMatch<Object?> route) {
    final waiting = _NestedLetIn.claim(_routeData);
    if (waiting == null) return;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        waiting.onFailure?.call(RouteNotFoundFailure(route.name));
        waiting.turnDown();
      })
      ..ensureVisualUpdate();
  }

  // When a widget above AutoTabsRouter rebuilds it from scratch, the new
  // router is set up before the outgoing one with the same key is disposed,
  // so the outgoing router still knows which tab was active.
  TabsRouter? _outgoingTabsRouter() {
    return _parent?.childControllers.whereType<TabsRouter>().lastWhereOrNull(
      (c) => c != this && c.key == key,
    );
  }

  void _pushAll(
    List<RouteMatch<Object?>> routes, {
    required bool isFromDefault,
  }) {
    for (final route in routes) {
      final data = _createRouteData<Object?>(route, routeData);
      try {
        _pages.add(data.buildPage());
        // A page that needs args it can't get is reported with the reason.
        // That is the error to catch.
      } on MissingRequiredParameterError catch (e, stackTrace) {
        if (isFromDefault) {
          // The new error carries the original message and stack trace.
          Error.throwWithStackTrace(
            FlutterError(
              'Can not automatically navigate to ${route.name} because it '
              'has required parameters. '
              'Routes must be added manually to AutoTabsRouter'
              '\n${e.message}',
            ),
            stackTrace,
          );
        }
        rethrow;
      }
    }
  }

  @override
  Future<List<ReevaluatableRouteMatch<Object?, Object?>>>
  _composeMatchesForReevaluate() async {
    final matches = <ReevaluatableRouteMatch<Object?, Object?>>[];
    for (final page in stack) {
      final match = page.routeData._route;
      final childCtrl = _innerControllerOfMatch(match.id);
      if (childCtrl == null) {
        // A tab whose nested router isn't built, not yet or no longer since
        // it keeps no state, has nothing inside to reevaluate. Its page is
        // left as it is: the pages it is still to open with, and the route
        // it was opened with, which a later navigate reads.
        matches.add(
          ReevaluatableRouteMatch(currentPage: page, originalMatch: match),
        );
        continue;
      }
      final reMatch = ReevaluatableRouteMatch<Object?, Object?>(
        currentPage: page,
        originalMatch: match.copyWith(
          children: await childCtrl._composeMatchesForReevaluate(),
        ),
      );
      page.routeData._onStartReevaluating(reMatch.originalMatch);
      matches.add(reMatch);
    }
    return matches;
  }

  List<RouteMatch<Object?>> _resolveRoutes(List<PageRouteInfo>? routes) {
    final List<PageRouteInfo> routesToUse;
    if (routes != null) {
      routesToUse = routes;
    } else {
      routesToUse = routeCollection.routes
          .where((e) => e is! RedirectRoute)
          .map((e) => PageRouteInfo(e.name))
          .toList();
    }
    return _matchAllOrReportFailure(routesToUse)!;
  }

  /// Resets [_pages] stack with given [routes]
  /// and sets `previousActiveRoute` as active index if provided
  void replaceAll(List<PageRouteInfo>? routes, int fromIndex) {
    final routesToPush = _resolveRoutes(routes);
    _listedTabArgs = [for (final route in routesToPush) route.args];
    _listedTabChildren = [
      for (final route in routesToPush) route.children ?? const [],
    ];
    final previousTabs = List.of(_pages);
    final previousActivePage = previousTabs.elementAtOrNull(fromIndex);
    final previousTabPage = switch (_previousIndex) {
      final index? => previousTabs.elementAtOrNull(index),
      null => null,
    };
    final previousPages = List.of(_pages);
    final previousHistory = [
      for (final index in _tabHistory) ?_pages.elementAtOrNull(index),
    ];

    _pages.clear();
    for (final route in routesToPush) {
      // A tab whose route is unchanged keeps its page, so its widget state
      // and nested router survive.
      final keptPage = previousPages.firstWhereOrNull(
        (p) => _isSameTab(p.routeData.route, route),
      );
      if (keptPage != null) {
        previousPages.remove(keptPage);
        _pages.add(keptPage);
      } else {
        _pushAll([route], isFromDefault: routes == null);
      }
    }
    final keptMatchIds = _pages.map((p) => p.routeData.matchId).toSet();
    _childControllers.removeWhere((c) => !keptMatchIds.contains(c.matchId));
    var targetIndex = _tabIndexAfterChange(previousActivePage);
    if (targetIndex == -1) {
      targetIndex = _homeTab == -1 ? 0 : _homeTab;
    }
    // Set directly, not through setActiveIndex: the old index points into the
    // old routes, so it can't be preloaded or reported to observers as the
    // previous tab. Each tabs view loads the active tab when it rebuilds with
    // the new routes.
    _activeIndex = targetIndex;
    // The previous tab is followed the same way, so both indexes name tabs of
    // the new routes. None when it is gone or is the one now active.
    final previousTab = _tabIndexAfterChange(previousTabPage);
    _previousIndex = previousTab == -1 || previousTab == _activeIndex
        ? null
        : previousTab;
    _tabHistory
      ..clear()
      ..addAll(
        {for (final page in previousHistory) _tabIndexAfterChange(page)}
            .where((index) => index != -1 && index != _activeIndex),
      );
    // A change still waiting for its guards follows its tab. It is called off
    // when the tab is gone, or a tab of other args took its place, as its
    // guards were asked about that tab only, and when the tab shows already.
    if (_pendingTab case final pendingTab?) {
      final pendingPage = previousTabs.elementAtOrNull(pendingTab);
      final index = pendingPage == null ? -1 : _pages.indexOf(pendingPage);
      if (index == -1 || index == _activeIndex) {
        _callOffPendingChange();
      } else {
        _pendingTab = index;
      }
    }
    // Another page is on screen: the url names it, and Android hears whether
    // the app takes back from it. This runs while the tabs widget builds, so
    // they are told after the frame. The user navigated to none of it, so the
    // url replaces the browser's entry, as a redirect does, and back never
    // returns to the url of a tab that left.
    if (_activePage != previousActivePage) {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          if (_isDisposed) return;
          markUrlStateForReplace();
          notifyAll(forceUrlRebuild: true);
        })
        ..ensureVisualUpdate();
    }
  }

  // Where the tab of [page], one of the tabs before they changed, is now:
  // its own page when it was kept, so of tabs that share a route the one
  // meant is found, else the first tab of its route. -1 when there is none.
  int _tabIndexAfterChange(AutoRoutePage<Object?>? page) {
    if (page == null) return -1;
    final kept = _pages.indexOf(page);
    if (kept != -1) return kept;
    return _pages.indexWhere((p) => p.routeData.name == page.routeData.name);
  }

  List<String> get _tabHistoryNames => [
    for (final index in _tabHistory)
      if (_pages.elementAtOrNull(index) case final page?) page.routeData.name,
  ];

  // The tab history over [routes] that [names] give, found by name, as the
  // tabs of another router can't be found by their pages: the tabs still
  // there, each once, without the active one.
  List<int> _historyOf(List<String> names, List<RouteMatch<Object?>> routes) =>
      {for (final name in names) routes.indexWhere((r) => r.name == name)}
          .where((index) => index != -1 && index != _activeIndex)
          .toList();

  bool _isSameTab(RouteMatch<Object?> a, RouteMatch<Object?> b) =>
      a.key == b.key &&
      a.args == b.args &&
      a.params == b.params &&
      a.queryParams == b.queryParams;

  @override
  Future<T?> _navigateAll<T extends Object?>(
    List<RouteMatch<Object?>> routes, {
    OnNavigationFailure? onFailure,
    bool isReevaluating = false,
    bool keepsUnnamedPages = false,
    int? link,
    VoidCallback? onLetIn,
    ValueChanged<StackRouter>? onGuardShowsPage,
  }) async {
    final ofLink = isReevaluating ? null : (link ?? root._startingLink);
    final routesToProcess = isReevaluating ? routes : routes.reversed.take(1);
    for (final mayUpdateRoute in routesToProcess) {
      final pageToUpdateIndex = _tabIndexOf(mayUpdateRoute);

      if (pageToUpdateIndex != -1) {
        if (!isReevaluating && _activeIndex != pageToUpdateIndex) {
          _changeTab(
            pageToUpdateIndex,
            route: mayUpdateRoute,
            onFailure: onFailure,
            keepsUnnamedPages: keepsUnnamedPages,
            link: ofLink,
            onLetIn: onLetIn,
          );
        } else {
          // A navigation to the tab on screen is the latest choice: it calls
          // off a change to another tab still waiting for its guards. A
          // setActiveIndex to it is not: the tabs views echo the active index
          // while a guard decides, and Flutter's TabController ignores a
          // choice of the selected tab.
          if (!isReevaluating && _pendingTab != null) _callOffPendingChange();
          final shouldNotify =
              mayUpdateRoute !=
              _pages.elementAtOrNull(pageToUpdateIndex)?.routeData._route;
          final routeToBeUpdated = _updateTabPage(
            pageToUpdateIndex,
            mayUpdateRoute,
            keepsUnnamedPages: keepsUnnamedPages,
          );
          if (shouldNotify) {
            notifyAll();
          }
          // A reevaluation goes on once the guards of a tab and of the pages
          // inside it have answered, as a stack asks its pages one after
          // another, so two guards that show a login page show one.
          final inside = isReevaluating && pageToUpdateIndex == _activeIndex
              ? _reevaluateActiveTab(routeToBeUpdated, onFailure: onFailure)
              : _navigateInsideTab(
                  routeToBeUpdated,
                  onFailure: onFailure,
                  isReevaluating: isReevaluating,
                  keepsUnnamedPages: keepsUnnamedPages,
                  link: ofLink,
                  onLetIn: onLetIn,
                  onGuardShowsPage: onGuardShowsPage,
                );
          if (isReevaluating) {
            await inside;
          } else if (inside != null) {
            unawaited(inside);
          }
        }
      }
      if (!isReevaluating && pageToUpdateIndex == -1) {
        if (_pages.isNotEmpty) {
          _turnDownRouteNotListed(
            mayUpdateRoute,
            link: ofLink,
            onFailure: onFailure,
          );
        } else {
          onLetIn?.call();
          _updateSharedPathData(
            queryParams: mayUpdateRoute.queryParams.rawMap,
            fragment: mayUpdateRoute.fragment,
          );
        }
      }
    }

    return null;
  }

  // Asks the guards of the active tab, which holds [route], again, as
  // reevaluateGuards asks those of every page of a stack. The other tabs are
  // asked when they are chosen. When the guards keep the tab out, the home
  // tab shows instead, or else the first, through its own guards. The pages
  // inside the tab are reevaluated once the guards let it stay, unless they
  // say otherwise with reevaluateNext. Answers once the pages inside the tab
  // are reevaluated, or null when that is done at once. A guard that throws
  // reports its error as an uncaught one, and the reevaluation goes on.
  //
  // A guard that returns without an answer lets go of the tab, as a stack's
  // guard lets go of its page: the tab leaves the screen at once, for the
  // tab a rejection would show, and the reevaluation goes on without it.
  // Once the guard lets it through, the tab shows again, through its guards,
  // unless the user chose another tab meanwhile. A guard that wants the tab
  // kept while it decides awaits its answer inside its call.
  Future<void>? _reevaluateActiveTab(
    RouteMatch<Object?> route, {
    OnNavigationFailure? onFailure,
  }) {
    final page = _activePage;
    final change = _tabChanges;
    // The latest tab change once the guard let go of the tab, or null while
    // it has not.
    int? changeAfterLetGo;
    void showAgain(ResolverResult result) {
      final index = page == null ? -1 : _pages.indexOf(page);
      if (_isDisposed ||
          !result.continueNavigation ||
          changeAfterLetGo != _tabChanges ||
          index == -1) {
        return;
      }
      if (_changeTab(index, remember: false, onFailure: onFailure)
          case final Future<void> shown) {
        unawaited(shown);
      }
    }

    Future<void>? apply(ResolverResult result) {
      if (changeAfterLetGo != null) {
        showAgain(result);
        return null;
      }
      // Another tab was chosen meanwhile, or the tabs are gone.
      if (_isDisposed || change != _tabChanges || _activePage != page) {
        return null;
      }
      if (!result.continueNavigation) {
        final fallback = _homeTab == -1 ? 0 : _homeTab;
        if (fallback == _activeIndex) return null;
        if (_changeTab(fallback, remember: false, onFailure: onFailure)
            case final Future<void> shown) {
          unawaited(shown);
        }
        return null;
      }
      if (!result.reevaluateNext) return null;
      // Children a guard set are new routes, not pages being reevaluated.
      // Their navigation answers once they are popped, so nothing waits for
      // it.
      final isReevaluating = (result.route.children ?? const []).every(
        (c) => c is ReevaluatableRouteMatch,
      );
      final inside = _navigateInsideTab(
        result.route,
        onFailure: onFailure,
        isReevaluating: isReevaluating,
      );
      if (isReevaluating || inside == null) return inside;
      unawaited(inside);
      return null;
    }

    final letGo = Completer<void>();
    final checked = _checkTabGuards(
      route,
      change: change,
      onFailure: onFailure,
      isReevaluating: true,
      onLetGo: () {
        if (!letGo.isCompleted) letGo.complete();
      },
    );
    if (checked is ResolverResult) return apply(checked);
    final applied = checked.then(
      apply,
      onError: (Object error, StackTrace stackTrace) =>
          Zone.current.handleUncaughtError(error, stackTrace),
    );
    return Future.any([
      applied,
      letGo.future.then((_) {
        if (_isDisposed || change != _tabChanges || _activePage != page) {
          // The tab left already: it doesn't come back.
          changeAfterLetGo = -1;
          return;
        }
        final fallback = _homeTab == -1 ? 0 : _homeTab;
        if (fallback != _activeIndex) {
          if (_changeTab(fallback, remember: false, onFailure: onFailure)
              case final Future<void> shown) {
            unawaited(shown);
          }
        }
        changeAfterLetGo = _tabChanges;
      }),
    ]);
  }

  // Puts [mayUpdateRoute] in the page of the tab at [index], and answers the
  // route the page now holds. With [keepsUnnamedPages], see
  // [_navigateAll], a route that names no children keeps the tab's.
  RouteMatch<Object?> _updateTabPage(
    int index,
    RouteMatch<Object?> mayUpdateRoute, {
    bool keepsUnnamedPages = false,
  }) {
    final oldData = _pages.elementAtOrNull(index)?.routeData;
    if (oldData == null) return mayUpdateRoute;
    var routeToBeUpdated = mayUpdateRoute.withId(oldData._route.id);
    // navigate to a route object that names no children, for a tab whose
    // nested router isn't built yet, keeps the pages the tab waits for, such
    // as the ones the tabs list gave it: they are what the tab shows when it
    // opens, by setActiveIndex as by navigate. A built nested router keeps
    // its own pages. A path names the whole state, so with no children the
    // tab opens with none.
    final oldChildren = List.of(oldData.pendingChildren);
    if (keepsUnnamedPages &&
        mayUpdateRoute is! ReevaluatableRouteMatch &&
        (mayUpdateRoute.children ?? const []).isEmpty &&
        oldChildren.isNotEmpty &&
        _innerControllerOfMatch(oldData.matchId) == null) {
      routeToBeUpdated = routeToBeUpdated.copyWith(children: oldChildren);
    }
    for (final ctr in _childControllers) {
      if (ctr.matchId == oldData.matchId) {
        ctr._isMarkedForDataUpdate = true;
      }
    }

    if (mayUpdateRoute is ReevaluatableRouteMatch) {
      _pages[index] = mayUpdateRoute.currentPage;
    } else {
      final data = _createRouteData<Object?>(
        _withTabArgs(routeToBeUpdated, _listedTabArgs.elementAtOrNull(index)),
        routeData,
      );
      _pages[index] = data.buildPage();
    }
    return routeToBeUpdated;
  }

  // The args each tab has in the routes the tabs are shown with, by index.
  // Not the page's own: those may be from a navigation, which a url replaces.
  var _listedTabArgs = const <Object?>[];

  // The children each tab has in the routes the tabs are shown with, by
  // index: the pages it opens with when the tabs list names them.
  var _listedTabChildren = const <List<RouteMatch<Object?>>>[];

  // The nested router of a tab goes while its tab stays when the tab keeps
  // no state (maintainState: false) and another tab shows. Built again, it
  // opens the pages its tab still waits for, else its initial child. With
  // neither it would show no page, so a tab whose router has no initial
  // child waits again for the pages the tabs list gave it, as it did when it
  // first opened. When the list gives it none, it waits for the pages of the
  // route it was opened with, such as a path's. A tab with an initial child
  // opens on that child, as before.
  @override
  void removeChildController(RoutingController childController) {
    super.removeChildController(childController);
    final index = _pages.indexWhere(
      (page) => page.routeData.matchId == childController.matchId,
    );
    final data = _pages.elementAtOrNull(index)?.routeData;
    if (data == null ||
        data.hasPendingChildren ||
        childController.matcher.match('') != null) {
      return;
    }
    final listed = _listedTabChildren.elementAtOrNull(index) ?? const [];
    final pages = listed.isNotEmpty
        ? listed
        : (data._route.children ?? const <RouteMatch<Object?>>[]);
    if (pages.isNotEmpty) data._pendingChildren = List.of(pages);
  }

  // A url can't hold constructor args, so a tab it opens gets [tabArgs], the
  // ones the tabs list gave it. Not when the url has params: a page's args
  // are then rebuilt from them, and listed ones would hide their values.
  RouteMatch<Object?> _withTabArgs(
    RouteMatch<Object?> route,
    Object? tabArgs,
  ) =>
      route.args != null ||
          route.params.isNotEmpty ||
          route.queryParams.isNotEmpty
      ? route
      : route.copyWith(args: tabArgs);

  // Navigates the nested router of the tab holding [route] to its children.
  // Answers once that router has, or null when the tab has none. [onLetIn]
  // runs once that router lets the navigation in; at once when the tab has
  // no nested router yet or [route] names no children for it.
  Future<void>? _navigateInsideTab(
    RouteMatch<Object?> route, {
    OnNavigationFailure? onFailure,
    bool isReevaluating = false,
    bool keepsUnnamedPages = false,
    int? link,
    VoidCallback? onLetIn,
    ValueChanged<StackRouter>? onGuardShowsPage,
  }) {
    // By match id: a tab sharing its route with another has its own nested
    // router.
    final inner = _innerControllerOfMatch(route.id);
    final children = route.children ?? const [];
    final isAsked = inner != null && children.isNotEmpty;
    if (!isAsked) onLetIn?.call();
    return inner?._navigateAll(
      children,
      onFailure: onFailure,
      isReevaluating: isReevaluating,
      keepsUnnamedPages: keepsUnnamedPages,
      link: link,
      onLetIn: isAsked ? onLetIn : null,
      onGuardShowsPage: onGuardShowsPage,
    );
  }

  // The tab [route] opens, or -1. A route with the match id of a tab's page,
  // as each route of a reevaluation has, is that tab's. Two tabs share a
  // route when both are children of the same parent route, such as one tab
  // per list item. The one meant has the path the route names, such as
  // 'item/2', when some tabs have it and others don't; then the one that
  // holds the route's first child, open or waiting to open.
  int _tabIndexOf(RouteMatch<Object?> route) {
    final ownTab = _pages.indexWhere(
      (page) => page.routeData.matchId == route.id,
    );
    if (ownTab != -1) return ownTab;
    final sameRoute = [
      for (var i = 0; i < _pages.length; i++)
        if (_pages[i].routeKey == route.key) i,
    ];
    if (sameRoute.length < 2) return sameRoute.firstOrNull ?? -1;
    final samePath = sameRoute
        .where(
          (index) =>
              _pages.elementAtOrNull(index)?.routeData._route.stringMatch ==
              route.stringMatch,
        )
        .toList();
    final tabs = samePath.isEmpty ? sameRoute : samePath;
    if (tabs.length < 2) return tabs.firstOrNull ?? -1;
    final childName = route.children?.firstOrNull?.name;
    bool doesHoldChild(int index) {
      final data = _pages.elementAtOrNull(index)?.routeData;
      if (data == null) return false;
      final pageNames =
          _innerControllerOfMatch(data.matchId)?.stackData.map((d) => d.name) ??
          data.route.children?.map((c) => c.name) ??
          const <String>[];
      return pageNames.contains(childName);
    }

    final holding = tabs.where(doesHoldChild).toList();
    final meant = holding.isEmpty ? tabs : holding;
    return meant.contains(_activeIndex)
        ? _activeIndex
        : (meant.firstOrNull ?? -1);
  }

  /// If page corresponding with [index]
  /// has an attached [StackRouter] returns it
  /// otherwise returns null
  StackRouter? stackRouterOfIndex(int index) {
    if (_childControllers.isEmpty) {
      return null;
    }
    final page = _pages.elementAtOrNull(index);
    if (page == null) return null;
    final innerRouter = _innerControllerOfMatch(page.routeData.matchId);
    if (innerRouter is StackRouter) {
      return innerRouter;
    }
    return null;
  }

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) {
    if (!ignoreChildRoutes) {
      final innerRouter = _innerControllerOfPage(_activePage?.routeData);
      if (innerRouter != null &&
          innerRouter.canPop(
            ignorePagelessRoutes: ignorePagelessRoutes,
            ignoreParentRoutes: true,
          )) {
        return true;
      }
    }
    if (!ignoreParentRoutes && _parent != null) {
      return _parent!.canPop(
        ignoreChildRoutes: true,
        ignorePagelessRoutes: ignorePagelessRoutes,
      );
    }
    return false;
  }

  @override
  void _updateSharedPathData({
    Map<String, Object?> queryParams = const {},
    String fragment = '',
    bool includeAncestors = false,
  }) {
    final newData = _pages.elementAtOrNull(activeIndex)?.routeData;
    if (newData == null) return;
    final route = newData.route;
    newData._updateRoute(
      route.copyWith(queryParams: Parameters(queryParams), fragment: fragment),
    );
    if (includeAncestors && _parent != null) {
      _parent!._updateSharedPathData(
        queryParams: queryParams,
        fragment: fragment,
      );
    }
  }

  @override
  bool get managedByWidget => false;
}

/// An implementation of a [RoutingController] that handles stack navigation
abstract class StackRouter extends RoutingController {
  /// Default constructor
  new({
    required this.key,
    required this.matchId,
    OnNestedNavigateCallBack? onNavigate,
    this._parent,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : _navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       _onNavigateCallback = onNavigate;
  @override
  final RoutingController? _parent;
  @override
  final Key key;

  @override
  final Key matchId;

  final GlobalKey<NavigatorState> _navigatorKey;
  final OnNestedNavigateCallBack? _onNavigateCallback;

  /// The pending routes handler for this controller
  @internal
  late final pendingRoutesHandler = PendingRoutesHandler();

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
    pagelessRoutesObserver.dispose();
    activeGuardObserver.dispose();
    _completeFuturesOf({
      ..._pagesAtLastLeaveReport,
      ..._pages,
      ..._takenOffByOpenBatches,
      ..._takenOffForNewPage,
      ..._setAsideByReplaceAll,
      ..._waitingForLetGoGuards,
    });
  }

  // Whether [dispose] was called; a navigation that resumes after awaiting a
  // guard stops here, since the router's page left the stack meanwhile.
  bool _isDisposed = false;

  // The navigations that could not start as they were called, see
  // [_canStartAtOnce], from the call until they start a microtask later. A
  // pop called meanwhile waits for them, so it pops the page the caller just
  // pushed rather than the one below it.
  final _landingPushes = <Future<void>>{};

  /// Whether a navigation called on this router has not started yet, as one
  /// called while widgets are built, which starts a microtask later.
  ///
  /// The app's own history asks it after a step back, to tell a navigation
  /// the router has taken from one still to come.
  @internal
  bool get hasNavigationWaitingToStart => _landingPushes.isNotEmpty;

  // The animations of pages the navigator popped, while they leave the
  // screen; see [waitForTransitions].
  final _leavingAnimations = <Animation<Object?>>{};

  void _addLeavingAnimation(Animation<Object?> animation) {
    if (!animation.isAnimating) return;
    _leavingAnimations.add(animation);
    void listener(AnimationStatus _) {
      if (animation.isAnimating) return;
      animation.removeStatusListener(listener);
      _leavingAnimations.remove(animation);
    }

    animation.addStatusListener(listener);
  }

  /// Whether a reevaluation is in progress
  bool _isReevaluating = false;

  // On the root router: how many times the guards were asked again, by a
  // change of the listenable or a call of [reevaluateGuards] on any router
  // of the app. A replaceAll that puts back pages it had set aside reads it
  // to tell whether a change passed them by, see [_replaceAllMatches].
  var _guardStateChanges = 0;

  // How many rounds in a row the reevaluation in progress has asked again:
  // 0 in the round a change started, see [_isAskingAgainDue].
  var _roundsAskedAgain = 0;

  // Whether the listenable changed while a guard of the reevaluation in
  // progress ran its check. That guard read the state before the change, so
  // its answer may be stale: once the reevaluation ends, the guards are asked
  // again, so the last change wins, as Flutter's Router drops the answer of
  // an older route parse when newer route information arrives. In a round
  // that asks again, only a change that is not the guard's own is followed
  // by another round, and [_kMaxAsksAgainInARow] rounds at most: a guard
  // that notifies the listenable from its own check would be asked without
  // end.
  var _isAskingAgainDue = false;

  // How many times [_isAskingAgainDue] was set, for the call that set it to
  // tell.
  var _askAgainRequests = 0;

  // The pages a reevaluation in progress holds off the stack itself until
  // their guards answer: the page of a guard that returned without an
  // answer, with the pages above it, and the page a guard's redirect
  // replaced. They go back on once their guards let them through.
  final _heldBackByReevaluation = <RouteData<Object?>>{};

  // How many reevaluations of this router's pages are in progress, the one
  // a router above runs here among them.
  var _reevaluationsInProgress = 0;

  // The pages of [_heldBackByReevaluation] whose guard let go of them: they
  // wait off the stack and the screen for its answer after the reevaluation
  // that asked it has ended, see [_awaitLetGoAnswer].
  final _waitingForLetGoGuards = <AutoRoutePage<Object?>>{};

  // The guards asked again that returned without an answer and let go of
  // their page or tab, until they answer. Nothing on screen waits for them,
  // and they may wait for something as long as a sign-in, so
  // [activeGuardObserver] no longer counts them: a loading indicator shown
  // from it would cover the app meanwhile. Each later reevaluation asks them
  // again without waiting for them, see [_composeMatchesForReevaluate].
  final _guardsLettingGo = <GuardEntry>[];

  // Moves the entries of [resolver], whose guard let go of its page, from
  // [activeGuardObserver] to [_guardsLettingGo] until it answers.
  void _letGoOfGuard(NavigationResolver resolver) {
    final entries = activeGuardObserver.value
        .where((entry) => identical(entry._resolver, resolver))
        .toList();
    if (entries.isEmpty) return;
    entries.forEach(activeGuardObserver._remove);
    _guardsLettingGo.addAll(entries);
    unawaited(
      resolver.future.then(
        (_) => _guardsLettingGo.removeWhere(entries.contains),
      ),
    );
  }

  // Whether the app took the page of [match] off since the reevaluation that
  // asks about it began, as replace, replaceAll, removeWhere and navigate
  // do. Such a page stays off, whatever its guard answers: a reevaluation
  // asks whether the pages on the stack may stay, and puts back only the
  // pages it holds back itself, see [_heldBackByReevaluation]. Never true of
  // a page of another router, such as the tab a tab's guard is asked about.
  bool _wasTakenOffDuringReevaluation(RouteMatch<Object?> match) {
    if (match is! ReevaluatableRouteMatch) return false;
    final data = match.currentPage.routeData;
    return identical(data.router, this) &&
        !_heldBackByReevaluation.contains(data) &&
        !_pages.any((page) => page.routeData == data);
  }

  // The pages as the last report of leaves saw them, bottom first.
  var _pagesAtLastLeaveReport = <AutoRoutePage<Object?>>[];

  // How the pages taken off the stack since the last report left, where the
  // change says it; others are told from the change itself.
  final _leaveKinds = <RouteData<Object?>, RouteLeaveKind>{};

  // While above 0, a reevaluation takes pages off and puts back the ones its
  // guards keep, so leaves wait for its end.
  var _leaveReportHolds = 0;

  // The pages a batch took off the stack as it put on the pages of the routes
  // before its last: their callers wait until the batch ends, when a page of
  // the batch may hold the screen and the wait of one of them, see
  // [_endWaitOfTakenOff].
  final _takenOffByOpenBatches = <AutoRoutePage<Object?>>{};

  // Whether a page is being taken off for a new page that goes on in its
  // place, as a top page that keeps no history is, or the page replace
  // replaces. The page answers its caller only once the new page is on, see
  // [_takenOffForNewPage].
  var _isTakingOffForNewPage = false;

  // The pages taken off for a new page, until that page is on the stack. The
  // new page may take over the screen of one of them, as a page of the same
  // route does: the screen then stays, and the code that opened it goes on
  // waiting for its result, as Flutter's Navigator keeps the route and its
  // future for a page of the same type and key. The others answer null, see
  // [_endWaitOfTakenOff].
  final _takenOffForNewPage = <AutoRoutePage<Object?>>[];

  void _markLeaving(
    Iterable<AutoRoutePage<Object?>> pages,
    RouteLeaveKind kind,
  ) {
    for (final page in pages) {
      _leaveKinds.putIfAbsent(page.routeData, () => kind);
      if (kind == .replaced) page.routeData._isReplaced = true;
    }
  }

  // The pages that replaceAll calls set aside for a page that went on in
  // their place while a guard decides. They come back if the guard rejects,
  // so until it answers no new page takes over the screen of one of them,
  // see [_shownTopTakenOverBy], and the code that opened one goes on waiting
  // for its result: it hears null once the page is gone for good, as the
  // guard lets the new pages in or the app replaces the page in their place.
  final _setAsideByReplaceAll = <AutoRoutePage<Object?>>{};

  // The replaceAll calls on this stack whose guards have not all answered,
  // told of each new page that goes on, see [_reportPageGoesOn].
  final _openReplacements = <_PagesReplacement>[];

  // Called right before a new page goes on this stack. A replaceAll that
  // waits for a guard hears of it: its pages to replace leave now when the
  // page is the guard's own, which the zone the calling code runs in tells,
  // or when the guard's call has returned without an answer, whoever puts
  // the page on then, see [_replaceAllMatches].
  void _reportPageGoesOn() {
    NavigationResolver._reportPageGoesOn(this);
    for (final replacement in List.of(_openReplacements)) {
      replacement.onPageGoesOn();
    }
  }

  // Called right after the new page of [data] went on this stack.
  void _reportPageWentOn(RouteData<Object?> data) {
    for (final replacement in List.of(_openReplacements)) {
      replacement.onPageWentOn(data);
    }
  }

  Future<T> _holdingLeaveReports<T>(Future<T> Function() change) async {
    _leaveReportHolds++;
    try {
      return await change();
    } finally {
      _leaveReportHolds--;
      _reportLeaves();
    }
  }

  @override
  void notifyListeners() {
    _reportLeaves();
    _noteListenersTold();
    super.notifyListeners();
  }

  // Tells each page that left the stack since the last report how it left,
  // and the page that was on top that a new page now covers it. A page taken
  // off with no recorded kind left by a pop when it was on top and nothing
  // took its place, was replaced when a new page did, and was removed when it
  // was below the top. A page that a new page of the same route takes over,
  // as a navigation to the route already shown does, stays on screen and
  // hasn't left.
  void _reportLeaves() {
    if (_leaveReportHolds > 0 || _isDisposed) return;
    final before = [for (final page in _pagesAtLastLeaveReport) page.routeData];
    final now = [for (final page in _pages) page.routeData];
    final takenOver = _takenOverScreens(_pagesAtLastLeaveReport, _pages);
    final previousPages = _pagesAtLastLeaveReport;
    _pagesAtLastLeaveReport = List.of(_pages);
    final kinds = Map.of(_leaveKinds);
    _leaveKinds.clear();
    final oldTop = before.lastOrNull;
    if (oldTop == null) return;
    final stillShown = now.toSet();
    final isNewTopNew = switch (now.lastOrNull) {
      final newTop? => !before.contains(newTop),
      null => false,
    };
    final leaves = <(RouteData<Object?>, RouteLeaveKind)>[
      for (final page in previousPages.reversed)
        if (!stillShown.contains(page.routeData) &&
            !takenOver.contains(page.routeData))
          (
            page.routeData,
            kinds[page.routeData] ??
                switch (page.routeData == oldTop) {
                  true when isNewTopNew => .replaced,
                  true => .popped,
                  false => .removed,
                },
          ),
      if (stillShown.contains(oldTop) && isNewTopNew) (oldTop, .covered),
    ];
    for (final (data, kind) in leaves) {
      data._reportLeave(kind);
    }
    final shownWaits = _pendingPopCompletersOf(_pages);
    _completeFuturesOf(
      previousPages.where(
        (page) =>
            !stillShown.contains(page.routeData) &&
            !shownWaits.contains(page.routeData._popCompleter) &&
            !_takenOffByOpenBatches.contains(page) &&
            !_setAsideByReplaceAll.contains(page) &&
            !_waitingForLetGoGuards.contains(page),
      ),
    );
  }

  // The pages of [before] whose screen a page of [after] takes over, so the
  // screen stays: the pairs Flutter's Navigator makes as it updates its
  // routes to new pages, by Page.canUpdate, first from the bottom, then from
  // the top, then the rest by key. Only one page takes over a screen, so of
  // two pages of one route that leave, the one whose screen no new page takes
  // over has left.
  static Set<RouteData<Object?>> _takenOverScreens(
    List<AutoRoutePage<Object?>> before,
    List<AutoRoutePage<Object?>> after,
  ) {
    final takenOver = <RouteData<Object?>>{};
    // Pairs the page of [before] at [oldAt] with the page of [after] at
    // [newAt] when the new page can take over its screen.
    bool pairs(int oldAt, int newAt) {
      final old = before.elementAtOrNull(oldAt);
      final page = after.elementAtOrNull(newAt);
      if (old == null || page == null || !page.canUpdate(old)) return false;
      takenOver.add(old.routeData);
      return true;
    }

    var bottom = 0;
    while (pairs(bottom, bottom)) {
      bottom++;
    }
    var oldTop = before.length - 1;
    var newTop = after.length - 1;
    while (oldTop >= bottom && newTop >= bottom && pairs(oldTop, newTop)) {
      oldTop--;
      newTop--;
    }
    final byKey = {
      for (final page in before.sublist(bottom, oldTop + 1)) page.key: page,
    };
    for (final page in after.sublist(bottom, newTop + 1)) {
      final old = byKey[page.key];
      if (old != null && page.canUpdate(old)) {
        takenOver.add(old.routeData);
        byKey.remove(page.key);
      }
    }
    return takenOver;
  }

  // The pop completers that the code which opened [pages] waits on.
  Set<Completer<Object?>> _pendingPopCompletersOf(
    Iterable<AutoRoutePage<Object?>> pages,
  ) => {for (final page in pages) ?page.routeData._pendingPopCompleter};

  // Completes with null the future that the push, navigate or replaceAll of
  // each of [pages] returned, as a removed route's does in Flutter, once the
  // page has left the stack for good: removed, replaced, or gone with its
  // router. A page that a new page took over, as a navigation to its screen
  // does, isn't passed here: the screen stays, and the new page holds its
  // future until the screen closes. Left pending, each call awaiting it stays
  // suspended and holds the pages it worked with, whose own futures older
  // calls await, so the pages an app left stayed in memory: one more on every
  // replaceAll, and in debug builds, which keep every local of a suspended
  // call, the nested routers of every link too.
  void _completeFuturesOf(Iterable<AutoRoutePage<Object?>> pages) {
    for (final page in pages) {
      page.routeData.onPopInvoked(null);
    }
  }

  /// Re-builds all routes in stack and reevaluate guarded
  /// once by re-visiting the onNavigation method when evaluation logic changes
  ///
  /// e.g when the user is no longer authenticated
  /// and there are auth-protected routes in the stack
  ///
  /// The guards of every page are asked, also those of the pages in a nested
  /// router, or in a tab, of a page that another page covers. The nested
  /// routers are asked one after another, from the bottom of the stack up, so
  /// a guard is asked only once the one before it has answered.
  ///
  /// While a guard's check runs, its page stays in the stack and on screen,
  /// with the pages above it; only the guard's answer closes it. A guard that
  /// returns without an answer, and without
  /// [NavigationResolver.redirectUntil], lets go of its page: the page leaves
  /// the stack and the screen at once, with the pages above it, while the
  /// code that opened it goes on waiting. Once the guard lets it through, the
  /// page goes back on top of the stack as it then is, and the pages that
  /// were above it follow as their guards let them; a rejection closes it for
  /// good. A guard that wants its page kept while it decides awaits its
  /// answer inside its call. Such a guard holds no later reevaluation up:
  /// each one asks it again without waiting for its answer, and
  /// [ActiveGuardObserver.guardInProgress] no longer counts it. The same
  /// holds for the guard of the active tab of a [TabsRouter], whose tab
  /// leaves the screen for the home tab until the guard lets it through.
  ///
  /// A page the app takes off while a guard still decides, as [replace],
  /// [replaceAll], [removeWhere] and [navigate] do, stays off whatever the
  /// guard then answers.
  ///
  /// Called again while a guard still runs its check, it asks the guards once
  /// more when that round ends, so the last change wins.
  Future<void> reevaluateGuards() {
    root._guardStateChanges++;
    return _reevaluateGuards(roundsAskedAgain: 0);
  }

  Future<void> _reevaluateGuards({required int roundsAskedAgain}) async {
    final requestsBefore = _askAgainRequests;
    final composed = await _composeMatchesForReevaluate();
    if (_isDisposed) return;
    // A page removed while the stack was composed, e.g. by a replaceAll called
    // right after the listenable changed, stays removed.
    final matches = composed
        .where((match) => _pages.contains(match.currentPage))
        .toList();
    // This change found a guard of the reevaluation in progress at its check:
    // that reevaluation asks the guards again once it ends, also when it has
    // ended by now. This call took the stale answer for its own, so it asks
    // no guard itself.
    final isLeftToNextRound = _askAgainRequests != requestsBefore;
    if (matches.isNotEmpty && !_isReevaluating && !isLeftToNextRound) {
      // A request the last reevaluation left when a guard threw is met by
      // this one.
      _isAskingAgainDue = false;
      _isReevaluating = true;
      _roundsAskedAgain = roundsAskedAgain;
      try {
        await _navigateAll(matches, isReevaluating: true);
      } finally {
        // Also when a guard throws: the stack is as it was, and later
        // reevaluations run.
        _isReevaluating = false;
        _roundsAskedAgain = 0;
      }
      if (_isAskingAgainDue) {
        _isAskingAgainDue = false;
        if (!_isDisposed) {
          await _reevaluateGuards(roundsAskedAgain: roundsAskedAgain + 1);
        }
        return;
      }
    }
    if (_isDisposed) return;
    notifyAll();
  }

  // Has the reevaluation in progress, of this router or of one above it, ask
  // its guards again once it ends; see [_isAskingAgainDue]. [isOwnChange]
  // says the change that asks for it is the checking guard's own.
  void _askAgainAfterReevaluation({required bool isOwnChange}) {
    for (
      RoutingController? router = this;
      router != null;
      router = router._parent
    ) {
      if (router is! StackRouter || !router._isReevaluating) continue;
      final rounds = router._roundsAskedAgain;
      final isAskedAgain =
          rounds == 0 || (!isOwnChange && rounds < _kMaxAsksAgainInARow);
      if (isAskedAgain) {
        router
          .._isAskingAgainDue = true
          .._askAgainRequests += 1;
      }
    }
  }

  @override
  Future<List<ReevaluatableRouteMatch<Object?, Object?>>>
  _composeMatchesForReevaluate() async {
    /// wait for the current child to finish its animation
    if (currentChild?.animationCompletion case final completion?) {
      await completion;
    }
    final alreadyEvaluated = <Key, List<AutoRouteGuard>>{};
    for (var i = 0; i < activeGuardObserver.value.length; i++) {
      final entry = activeGuardObserver.value[i];
      final resolver = entry._resolver;
      if (resolver.isResolved) continue;
      // The guard is running its check, which began before this change.
      if (resolver._waitingCompleter != null) {
        if (resolver.route is ReevaluatableRouteMatch) {
          // Of a page being reevaluated.
          _askAgainAfterReevaluation(isOwnChange: resolver._isOwnCodeRunning);
        } else if (!resolver._isOwnCodeRunning && !resolver._isWaitingOnUser) {
          // Of a navigation: it is asked again before its page goes in.
          resolver._isAnswerStale = true;
        }
      }
      resolver._isReevaluating = true;

      final result = await resolver.checkGuard(entry.guard, this);
      if (result.continueNavigation) {
        alreadyEvaluated
            .putIfAbsent(result.route.id, () => [])
            .add(entry.guard);
      }
    }
    // A guard that let go of its page holds no reevaluation up: it is asked
    // again, and its page comes back once it lets it through, but nothing
    // waits for it here.
    for (final entry in List.of(_guardsLettingGo)) {
      if (entry._resolver.isResolved) continue;
      unawaited(entry._resolver.checkGuard(entry.guard, this));
    }

    final matches = <ReevaluatableRouteMatch<Object?, Object?>>[];
    for (final page in stack) {
      var match = page.routeData._route;
      if (alreadyEvaluated.containsKey(match.id)) {
        match = match.copyWith(evaluatedGuards: alreadyEvaluated[match.id]);
      }
      final childCtrl = _innerControllerOfMatch(match.id);
      if (childCtrl != null) {
        final childMatches = await childCtrl._composeMatchesForReevaluate();
        match = match.copyWith(children: childMatches);
      } else if (page.routeData.hasPendingChildren) {
        // A page whose nested router is not built yet keeps the pages it is
        // to open with, as one that replaceAll set aside and put back does,
        // see [_replaceAllMatches]: they are not the children its route
        // came with.
        match = match.copyWith(
          children: List.of(page.routeData.pendingChildren),
        );
      }
      page.routeData._onStartReevaluating(match);

      /// the route maybe removed from stack at this point
      if (stackData.any((e) => e._route.id == match.id)) {
        matches.add(
          ReevaluatableRouteMatch(currentPage: page, originalMatch: match),
        );
      }
    }
    return matches;
  }

  @override
  int get stateHash => super.stateHash ^ hasPagelessTopRoute.hashCode;

  /// The page-less route observer of this controller
  final pagelessRoutesObserver = PagelessRoutesObserver()
    ..onPagelessRouteIn = NavigationResolver._reportPagelessRouteGoesOn;

  /// The active guards observer of this controller
  final activeGuardObserver = ActiveGuardObserver();

  /// Navigator key passed to [Navigator.key]
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) {
    if (_pages.length > 1 || (!ignorePagelessRoutes && hasPagelessTopRoute)) {
      return true;
    }

    if (!ignoreChildRoutes && _pages.isNotEmpty) {
      final innerRouter = _innerControllerOfPage(_pages.last.routeData);
      if (innerRouter != null &&
          innerRouter.canPop(
            ignoreParentRoutes: true,
            ignorePagelessRoutes: ignorePagelessRoutes,
          )) {
        return true;
      }
    }

    if (!ignoreParentRoutes && _parent != null) {
      return _parent!.canPop(
        ignorePagelessRoutes: ignorePagelessRoutes,
        ignoreChildRoutes: true,
      );
    }
    return false;
  }

  @override
  RouteData<Object?> get current => currentChild ?? routeData;

  @override
  RouteData<Object?>? get currentChild {
    if (_pages.isNotEmpty) {
      return _pages.last.routeData;
    }
    return null;
  }

  /// Pushes a raw widget to [Navigator]
  ///
  /// Widgets pushed using this method
  /// don't have paths nor effect url
  Future<T?> pushWidget<T extends Object?>(
    Widget widget, {
    RouteTransitionsBuilder? transitionBuilder,
    bool fullscreenDialog = false,
    Duration transitionDuration = const Duration(milliseconds: 300),
    bool opaque = true,
  }) {
    final navigator = _navigatorKey.currentState;
    assert(navigator != null, 'The navigator of this router is not mounted.');
    return navigator!.push<T>(
      AutoPageRouteBuilder<T>(
        child: widget,
        fullscreenDialog: fullscreenDialog,
        transitionBuilder: transitionBuilder,
        transitionDuration: transitionDuration,
        opaque: opaque,
      ),
    );
  }

  /// Pushes a [Route] to [Navigator]
  ///
  /// Routes pushed using this method
  /// don't have paths nor effect url
  Future<T?> pushNativeRoute<T extends Object?>(Route<T> route) {
    final navigator = _navigatorKey.currentState;
    assert(navigator != null, 'The navigator of this router is not mounted.');
    return navigator!.push(route);
  }

  @override
  RoutingController _topMostRouter({bool ignorePagelessRoutes = false}) {
    if (_childControllers.isNotEmpty &&
        (ignorePagelessRoutes || !hasPagelessTopRoute)) {
      final innerRouter = _innerControllerOfPage(currentChild);
      if (innerRouter != null) {
        return innerRouter._topMostRouter(
          ignorePagelessRoutes: ignorePagelessRoutes,
        );
      }
    }
    return this;
  }

  @override
  RouteData<Object?> get topRoute =>
      _topMostRouter(ignorePagelessRoutes: true).current;

  /// Whether the top-most route of this controller is page-less
  bool get hasPagelessTopRoute =>
      hasEntries && pagelessRoutesObserver.hasPagelessTopRoute;

  @override
  void _updateSharedPathData({
    Map<String, Object?> queryParams = const {},
    String fragment = '',
    bool includeAncestors = false,
  }) {
    for (var index = 0; index < _pages.length; index++) {
      final data = _pages[index].routeData;
      final route = data.route;
      data._updateRoute(
        route.copyWith(
          queryParams: Parameters(queryParams),
          fragment: fragment,
        ),
      );
    }
    if (includeAncestors && _parent != null) {
      _parent!._updateSharedPathData(
        queryParams: queryParams,
        fragment: fragment,
        includeAncestors: includeAncestors,
      );
    }
  }

  /// Pops the top route of this router's navigator, unless a [PopScope] or
  /// a nested router takes the pop, and otherwise defers to the parent router.
  ///
  /// Works through [Navigator.maybePop], so [PopScope]s are respected. When
  /// the top page holds an [AutoRouter] with more than one page, that nested
  /// router pops its own top page instead, and the page holding it stays.
  /// This is the same order system back uses.
  ///
  /// When this router's navigator has nothing to pop, or no navigator is
  /// mounted because the router has no pages, the call goes to the parent
  /// router. [result] is passed to the popped route.
  ///
  /// Completes with `true` when a route was popped or a [PopScope] handled
  /// the pop, and `false` when no router up to the root could pop.
  @override
  @optionalTypeArgs
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    if (_landingPushes.isNotEmpty) {
      await Future.wait(_landingPushes);
    }
    // The navigator hands the pop to the nested router on top, through that
    // router's navigator, which knows neither of a page not built yet nor
    // of one that just left. So the routers from the one on top down to
    // this one each take their step first, as the router on top does for
    // maybePopTop and the system back button.
    for (final router in _stackRoutersFromTop()) {
      if (router._didPopUnbuiltTop(result)) return true;
      router._removeLeftRoutesOverTop();
    }
    final navigator = _navigatorKey.currentState;
    if (await navigator?.maybePop<T>(result) ?? false) {
      return true;
    } else if (_parent != null) {
      return await _parent!.maybePop(result);
    }
    return false;
  }

  /// Pop current route regardless if it's the last
  /// route in stack or the result of it's PopScopes
  /// see [Navigator.pop]
  ///
  /// Right after [push] or [replace] of a route no guard makes wait, the pop
  /// closes that page, before it is ever shown; where the push starts a
  /// microtask later, see [push], the pop waits for it.
  /// A push still waiting on a guard is not waited for: the guard may be
  /// waiting on the very route this pop closes, such as a dialog.
  ///
  /// On a router built by `AutoRouter.declarative`, popping the only page
  /// closes the page that holds the router, as the router's routes callback
  /// decides its pages.
  @override
  @optionalTypeArgs
  void pop<T extends Object?>([T? result]) {
    if (_landingPushes.isNotEmpty) {
      unawaited(Future.wait(_landingPushes).then((_) => pop<T>(result)));
      return;
    }
    if (_didPopUnbuiltTop(result)) return;
    _removeLeftRoutesOverTop();
    final navigator = _navigatorKey.currentState;
    // The routes callback of a declarative router decides its pages, so its
    // only page can't be popped from under it: the page holding it closes.
    if (managedByWidget && navigator?.canPop() == false) {
      _parent?.pop<T>(result);
    } else {
      navigator?.pop(result);
    }
  }

  // The stack routers from the one on top of this router's pages down to
  // this router, which is the last.
  List<StackRouter> _stackRoutersFromTop() => [
    ..._topMostRouter()
        ._buildRoutersHierarchy()
        .whereType<StackRouter>()
        .takeWhile((router) => router != this),
    this,
  ];

  // Removes the top page when the navigator has not built it yet, as right
  // after a push, and completes it with [result]. Navigator.pop would pop
  // the page below it instead. The last page is never removed this way: right
  // after replaceAll or navigate it is the only page, and the pop goes to what
  // the navigator has built, as a back on a single-page router does.
  bool _didPopUnbuiltTop(Object? result) {
    final navigator = _navigatorKey.currentState;
    final top = _pages.lastOrNull;
    if (navigator == null ||
        top == null ||
        _pages.length < 2 ||
        navigator.widget.pages.contains(top)) {
      return false;
    }
    top.routeData.onPopInvoked(result);
    _removeRoute(top.routeData._route, notify: false);
    _notifyOfClosedUnbuilt([top]);
    return true;
  }

  // Runs a popUntil from the top down: first over the pages on top that the
  // navigator has not built yet, which leave in the call (see
  // [_didPopUnbuiltPagesUntil]), then over the built ones, through [popBuilt].
  // A pop that is not scoped walks the routers from the one on top down to
  // the root, as they are at the call: [popBuilt] gets them when it runs in
  // the call, since a page that left may have uncovered a nested router that
  // the same pop a frame later would not walk. Where the pop has to wait for
  // the navigators, [popBuilt] gets null and walks the routers of that time,
  // as before.
  void _popUntilFromUnbuiltDown(
    RoutePredicate predicate, {
    required bool isScoped,
    required bool keepsFirstPage,
    required void Function(List<StackRouter>? walked) popBuilt,
  }) {
    final routers = isScoped
        ? [this]
        : _topMostRouter()
              ._buildRoutersHierarchy()
              .whereType<StackRouter>()
              .toList();
    final top = routers.firstOrNull;
    if (top == null) return;
    final count = top._pages.length;
    final isReached = top._didPopUnbuiltPagesUntil(
      predicate,
      // Only the last router walked keeps its first page.
      keepsFirstPage: keepsFirstPage && top == routers.lastOrNull,
    );
    if (isReached) return;
    if (top._pages.length < count) {
      // The pages left to ask are all built.
      popBuilt(routers);
      return;
    }
    _whenPagesBuilt(isScoped: isScoped, () => popBuilt(null));
  }

  // Tells the listeners, as [notifyAll] does, that [closed] were taken off
  // the stack before the navigator built them, and rebuilds the url. No
  // navigator reports the pop of such a page, so the app's own history is
  // told here to drop its entries, or a later back() would open it again.
  void _notifyOfClosedUnbuilt(Iterable<AutoRoutePage<Object?>> closed) {
    notifyListeners();
    navigationHistory.rebuildUrlAfterClosingUnbuilt([
      for (final page in closed) page.routeData.matchId,
    ]);
    if (!isRoot) root.notifyListeners();
  }

  // The pages the app took off the stack for good, as replace, removeLast,
  // removeWhere and pushAndPopUntil do, until the navigator is rebuilt
  // without them. Each with the pageless routes that lay over its route
  // then, and with [_notifications] as it was then.
  final _leftSinceBuild =
      <
        AutoRoutePage<Object?>,
        ({List<Route<Object?>> coveredBy, int notifications})
      >{};

  // How many times this router told its listeners of a change. Each has the
  // navigator rebuilt with the frame that follows.
  var _notifications = 0;

  // Whether [_forgetLeftAfterFrame] already waits for the next frame.
  var _isForgettingLeftAfterFrame = false;

  void _noteLeft(AutoRoutePage<Object?> page) {
    final route = pagelessRoutesObserver.routeOf(page);
    // A page not built yet has no route to tell from the one under it.
    if (route == null) return;
    _leftSinceBuild[page] = (
      coveredBy: pagelessRoutesObserver.pagelessRoutesOver(route),
      notifications: _notifications,
    );
  }

  // Called as this router tells its listeners of a change.
  void _noteListenersTold() {
    _notifications++;
    _forgetLeftAfterFrame();
  }

  // Drops, after the next frame, the notes of the pages the navigator no
  // longer shows then. That frame rebuilds the navigator without the pages
  // the listeners were told of. A page taken off after that build, as from
  // another callback at the frame's end, is still shown: its note stays for
  // the frame after.
  void _forgetLeftAfterFrame() {
    final isRebuildOnItsWay = _leftSinceBuild.values.any(
      (left) => left.notifications < _notifications,
    );
    if (!isRebuildOnItsWay || _isForgettingLeftAfterFrame) return;
    _isForgettingLeftAfterFrame = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _isForgettingLeftAfterFrame = false;
      final shown = _navigatorKey.currentState?.widget.pages ?? const [];
      _leftSinceBuild.removeWhere((page, _) => !shown.contains(page));
      _forgetLeftAfterFrame();
    });
  }

  // Takes from the navigator the routes of pages the app took off the stack
  // for good and that still lie over its top page, with the pageless routes
  // that lay over them. The page a replace or removeLast took off keeps its
  // route until the navigator is rebuilt, with the next frame, and
  // Navigator.pop and maybePop act on the navigator's top route: a pop
  // before that frame would close that route, a page already gone, and
  // leave the stack's top page open. Flutter's own Navigator no longer
  // counts a route as present from the call that replaced or removed it, so
  // its next pop takes the route below.
  //
  // The navigator stays as it is when what lies over the top page is not
  // gone, or is what the user sees and a pop is meant for:
  // - a page that is off the stack only until a guard answers, which a
  //   reevaluation holds back or a replaceAll or a batch set aside. It is
  //   still on screen and may come back.
  // - a page taken off without the listeners being told, as with
  //   `notify: false`. No rebuild is on its way, so it stays on screen, and
  //   a pop closes its route.
  // - a dialog or other pageless route opened after the page under it left.
  void _removeLeftRoutesOverTop() {
    final navigator = _navigatorKey.currentState;
    final top = _pages.lastOrNull;
    if (navigator == null || top == null) return;
    final shown = navigator.widget.pages;
    final topIndex = shown.indexOf(top);
    // A top page not built yet has no route for a pop to reach.
    if (topIndex == -1) return;
    final gone = <Route<Object?>>[];
    for (final page in shown.skip(topIndex + 1).toList().reversed) {
      final route = pagelessRoutesObserver.routeOf(page);
      // A route already popped is leaving by itself.
      if (route == null || route.navigator != navigator || !route.isActive) {
        continue;
      }
      final left = _leftSinceBuild[page];
      final mayComeBack =
          _setAsideByReplaceAll.contains(page) ||
          _takenOffByOpenBatches.contains(page) ||
          page is AutoRoutePage &&
              _heldBackByReevaluation.contains(page.routeData);
      final isRebuildOnItsWay =
          left != null && left.notifications < _notifications;
      if (!isRebuildOnItsWay || mayComeBack) return;
      final overItNow = pagelessRoutesObserver.pagelessRoutesOver(route);
      if (!overItNow.every(left.coveredBy.contains)) return;
      gone
        ..addAll(overItNow)
        ..add(route);
    }
    gone.forEach(navigator.removeRoute);
  }

  /// Removes the very last entry from [_pages]
  bool removeLast() {
    _markRemovedByApp(_pages.reversed.take(1));
    return _removeLast();
  }

  /// Removes given [route] and any corresponding controllers
  ///
  /// A [route] kept from before a navigation reached its screen again, such as
  /// one with new query params, still names that screen and removes it, as
  /// Flutter's [Navigator.removeRoute] removes a route it kept for a new page.
  ///
  /// finally calls [notifyAll] if notify is true
  void removeRoute(RouteData<Object?> route, {bool notify = true}) {
    // The page showing the screen now holds the screen's match id, whether or
    // not it is the page [route] was built for.
    final shown = _pages.lastWhereOrNull(
      (page) => page.routeData.matchId == route.matchId,
    );
    _markRemovedByApp([?shown]);
    _removeRoute(route._route, notify: notify);
  }

  // The app takes [pages] off the stack by its own call, so each leaves as
  // removed and keeps its route from a new page of the same route.
  void _markRemovedByApp(Iterable<AutoRoutePage<Object?>> pages) {
    for (final page in pages) {
      page.markRemoved();
    }
    _markLeaving(pages, .removed);
  }

  /// Called when Page route is popped
  /// this is not called when pageless routes are popped e.g popping a dialog
  /// that does not use [PageRoute] will not trigger this method
  void onPopPage(AutoRoutePage<Object?> page) {
    if (!_pages.contains(page)) return;
    _markLeaving([page], .popped);
    _pages.remove(page);
    _shareTopPathData();
    notifyListeners();
    navigationHistory.rebuildUrlAfterPop(poppedPageId: page.routeData.matchId);
  }

  void _removeRoute(RouteMatch<Object?> route, {bool notify = true}) {
    final pageIndex = _pages.lastIndexWhere(
      (p) => p.routeData.matchId == route.id,
    );
    if (pageIndex != -1) {
      final page = _pages.removeAt(pageIndex);
      _noteLeft(page);
      // Removed pages may be disposed without a pop callback from Navigator.
      // A page taken off for a new page waits until that page is on.
      if (_isTakingOffForNewPage) {
        _takenOffForNewPage.add(page);
      } else {
        page.routeData.onPopInvoked(null);
      }
    }
    _shareTopPathData();
    if (notify) {
      notifyAll(forceUrlRebuild: true);
    }
  }

  // Shares the query params and fragment the page now on top was opened with,
  // after the page above it was removed.
  void _shareTopPathData() {
    final top = _pages.lastOrNull?.routeData;
    _updateSharedPathData(
      queryParams: top?._ownQueryParams.rawMap ?? const {},
      fragment: top?._ownFragment ?? '',
      includeAncestors: true,
    );
  }

  void _onNavigate(List<RouteMatch<Object?>> routes) {
    _onNavigateCallback?.call(routes);
  }

  bool _removeLast({bool notify = true}) {
    var didRemove = false;
    if (_pages.isNotEmpty) {
      // Not removeRoute, which counts the page as removed: callers that push
      // in its place count it as replaced.
      _removeRoute(_pages.last.routeData._route, notify: notify);
      didRemove = true;
    }
    return didRemove;
  }

  @override
  List<AutoRoutePage<Object?>> get stack => .unmodifiable(_pages);

  /// Adds the corresponding page to given [route] to the [_pages] stack
  ///
  /// A [route] with no guard, or whose guards each answer in their own call,
  /// as one that reads a flag and calls `next` does, is on the stack as this
  /// call returns, as a route is in the history as [Navigator.push] returns.
  /// A call made right after it, such as [replace], [replaceAll] or
  /// [removeLast], acts on its page. The same holds for [pushAll],
  /// [replaceAll], [navigate] and their kin.
  ///
  /// A guard that awaits before it answers, or shows a page of its own, makes
  /// the push wait for it. A call made meanwhile does not wait: it acts on
  /// the stack as it is, without the page.
  ///
  /// Called while widgets are built, as from `initState`, the push starts a
  /// microtask later, since the router's listeners may not rebuild widgets
  /// during a build. Several such calls start in the order they were made,
  /// but one that takes pages off, such as [replace], picks them as it is
  /// called, before the page of a push made just before it is on.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  @optionalTypeArgs
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    return await _findStackScope(route)._push(route, onFailure: onFailure);
  }

  StackRouter _findStackScope(PageRouteInfo route) {
    final stackRouters = _topMostRouter(ignorePagelessRoutes: true)
        ._buildRoutersHierarchy()
        .whereType<StackRouter>();
    return stackRouters.firstWhere(
      (c) => c._canHandleNavigation(route),
      orElse: () => this,
    );
  }

  /// Inserts the corresponding page to given [route] to the [_pages] stack
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  Future<void> insert(
    PageRouteInfo route, {
    int index = 0,
    OnNavigationFailure? onFailure,
  }) {
    return _findStackScope(route)
        ._push(route, onFailure: onFailure, insertAt: index);
  }

  // Not async: its future is the last page's, which a page that reaches the
  // screen already shown keeps until the screen closes. A suspended call
  // would hold the pages and routers it took off until then, in debug builds,
  // which keep every local of a suspended call.
  //
  // The pages it takes off, those above the pages it keeps and the page the
  // first route reaches again with every page above it, stay on the stack
  // until the guards of that route let it through. A route a guard rejects
  // leaves the stack as it was, with its pages, its url and the children of
  // their nested routers, as a canceled traversal to an entry already in the
  // history leaves the current entry on the web and an unwind segue that
  // isn't performed leaves its view controllers on iOS and macOS. While a
  // guard decides, the stack it reads is the one on screen, as Flutter's
  // Router keeps building the current pages while its delegate waits.
  Future<T?> _popUntilOrPushAll<T extends Object?>(
    List<RouteMatch<Object?>> matches, {
    required Completer<void> pushed,
    required ValueChanged<RouteMatch<Object?>> onLastRouteAdded,
    // Told, with what takes them off, when the pages above the page the
    // navigation reaches again stay until its nested router lets it in.
    required ValueChanged<VoidCallback> onPagesAboveHeld,
    OnNavigationFailure? onFailure,
    bool isReevaluating = false,
    _PagesReplacement? replacement,
    int? link,
    ValueChanged<StackRouter>? onGuardShowsPage,
  }) {
    // replaceAll reaches no page again: [replacement] takes every page off
    // once every guard has let [matches] through, and their pages go on in
    // the same step.
    if (replacement != null) {
      return _pushAllGuarded(
        matches,
        onFailure: onFailure,
        updateAncestorsPathData: false,
        goesInAtOnce: true,
        pushed: pushed,
        onLastRouteAdded: onLastRouteAdded,
        replacement: replacement,
        link: link,
        onGuardShowsPage: onGuardShowsPage,
      );
    }
    final (:kept, :end) = isReevaluating
        ? (kept: 0, end: _pages.length)
        : _pagesKeptUnderTarget(matches);
    final toPush = kept == 0 ? matches : matches.sublist(kept);
    final anchor = toPush.firstOrNull;
    if (anchor == null) return Future.value();
    // The anchor page is the first one from the top with its key, among the
    // pages that stay.
    final staying = _pages.sublist(0, end);
    // A reevaluation asks the guards of the pages where they are, so it
    // reaches none again and takes none off here.
    final anchorPage = isReevaluating
        ? null
        : staying.lastWhereOrNull((p) => p.routeKey == anchor.key);
    final anchorId = anchorPage?.routeData.matchId;
    if (anchorId != null) {
      // use the existing match id to avoid breaking child controllers
      toPush[0] = anchor.withId(anchorId);
    }
    // Let go once used, so the call that waits on the last page doesn't hold
    // the pages that left.
    List<AutoRoutePage<Object?>>? leaving = _pages.sublist(
      anchorPage == null ? end : staying.lastIndexOf(anchorPage),
    );
    // The anchor alone goes on again, into its nested router, which asks its
    // own guards: the pages above it stay until they let the navigation in,
    // as the dialogs over it do, and stay if they turn it down. The anchor
    // goes back in its own place under them meanwhile.
    final holdsPagesAbove =
        anchorPage != null &&
        anchorId != null &&
        toPush.length == 1 &&
        (anchor.children?.isNotEmpty ?? false) &&
        _innerControllerOfMatch(anchorId) != null &&
        identical(leaving.firstOrNull, anchorPage) &&
        leaving.length > 1;
    // Where the anchor was, once it has left for its new page.
    int? anchorIndex;
    return _pushAllGuarded(
      toPush,
      onFailure: onFailure,
      updateAncestorsPathData: false,
      isReevaluating: isReevaluating,
      pushed: pushed,
      onLastRouteAdded: onLastRouteAdded,
      link: link,
      onGuardShowsPage: onGuardShowsPage,
      lastPageAt: holdsPagesAbove ? () => anchorIndex : null,
      onFirstRouteAccepted: () {
        // A page popped while the guards decided has left already. And a
        // later navigation to the same page, let in while these guards
        // decided, has put its own page in the anchor's place, with the
        // anchor's match id: that page leaves for this one, which takes over
        // its screen, or the stack would hold two pages with one key, which
        // Flutter's Navigator forbids.
        final pagesLeaving = leaving ?? const [];
        leaving = null;
        bool isAnchor(AutoRoutePage<Object?> page) =>
            anchorId != null && page.routeData.matchId == anchorId;
        if (holdsPagesAbove) {
          final above = pagesLeaving.where((page) => !isAnchor(page)).toSet();
          onPagesAboveHeld(() {
            final left = _pages.where(above.contains).toList();
            above.clear();
            if (left.isEmpty || _isDisposed) return;
            _markLeaving(left, .removed);
            _pages.removeWhere(left.contains);
            notifyAll(forceUrlRebuild: true);
          });
        }
        final left = _pages
            .where(
              (page) =>
                  (pagesLeaving.contains(page) && !holdsPagesAbove) ||
                  isAnchor(page),
            )
            .toList();
        if (holdsPagesAbove) {
          final index = _pages.indexWhere(isAnchor);
          anchorIndex = index == -1 ? null : index;
        }
        _markLeaving(left, .removed);
        _pages.removeWhere(left.contains);
        if (anchorId == null) return;
        for (final ctr in _childControllers) {
          if (ctr.matchId == anchorId) {
            ctr._isMarkedForDataUpdate = true;
          }
        }
      },
    );
  }

  // How many of [matches], save the last, find a page they would build again
  // as it is, from the page the first one matches up, and the end of the
  // pages that stay: the pages above the kept ones leave, except one the next
  // match opens again, which is left for the caller. The kept pages' widgets
  // are not created and built again, as with go_router
  // (flutter/flutter#147639). A page holding a nested router is built again,
  // which updates its router.
  ({int kept, int end}) _pagesKeptUnderTarget(
    List<RouteMatch<Object?>> matches,
  ) {
    final none = (kept: 0, end: _pages.length);
    final start = _pages.lastIndexWhere(
      (p) => p.routeKey == matches.firstOrNull?.key,
    );
    if (start == -1) return none;
    var kept = 0;
    while (kept < matches.length - 1) {
      final data = _pages.elementAtOrNull(start + kept)?.routeData;
      if (data == null ||
          data._route != matches.elementAtOrNull(kept) ||
          _innerControllerOfMatch(data.matchId) != null) {
        break;
      }
      kept++;
    }
    if (kept == 0) return none;
    final next = start + kept;
    final nextPage = _pages.elementAtOrNull(next);
    final isNextLeaving =
        nextPage != null &&
        nextPage.routeKey != matches.elementAtOrNull(kept)?.key;
    return (kept: kept, end: isNextLeaving ? next : _pages.length);
  }

  // Whether a navigation that adds pages, such as push, replace, pushAll,
  // replaceAll or navigate, starts as it is called: its guards are asked in
  // the call, and when each answers in its own call, the pages are on the
  // stack as the call returns, as Navigator.push puts its route in the
  // history at once. A call made right after it, such as replace, navigate or
  // removeLast, then acts on the stack with those pages.
  //
  // Not while an earlier navigation of this router still waits for its turn:
  // this one takes its turn behind it, in the order of the calls. And not
  // while widgets are built, where Navigator.push throws: the router's
  // listeners rebuild the widgets that show it, which a build forbids (#853).
  // That covers the frame's build, layout and paint, the first build of the
  // app, which runs outside a frame before the root element is set, and a
  // router no widget shows yet. Such a navigation starts a microtask later,
  // see [_takeTurn].
  bool get _canStartAtOnce {
    if (_landingPushes.isNotEmpty) return false;
    if (root.pagelessRoutesObserver.navigator == null) return false;
    final binding = WidgetsBinding.instance;
    return binding.rootElement != null &&
        binding.schedulerPhase != .persistentCallbacks;
  }

  // Notes a navigation that can't start as it is called, see
  // [_canStartAtOnce]. Its caller waits one microtask, then hands what this
  // returns to [_endTurn]. Every such navigation waits that one microtask,
  // so they start in the order they were called.
  Completer<void> _takeTurn() {
    final turn = Completer<void>();
    _landingPushes.add(turn.future);
    return turn;
  }

  // Ends the wait [_takeTurn] noted. What waits on it, such as a pop, runs
  // in a later microtask, after the navigation that starts now has added the
  // pages its guards let through in their own call.
  void _endTurn(Completer<void> turn) {
    _landingPushes.remove(turn.future);
    turn.complete();
  }

  // Why a router that AutoRouter.declarative builds can't push its own pages,
  // and what to do instead.
  String get _managedByWidgetMessage =>
      'The router of ${routeData.name} is built by AutoRouter.declarative, '
      'so the list its routes callback '
      'returns decides its pages, and push, replace and their kin can not '
      'change them. Add the route to the list '
      'that routes callback returns, from state your app updates, or build '
      'this router with AutoRouter() to '
      'navigate it with push and replace.';

  @optionalTypeArgs
  Future<T?> _push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
    bool notify = true,
    ValueChanged<RouteMatch<Object?>>? onMatch,
    VoidCallback? onAccepted,
    int? insertAt,
  }) async {
    assert(!managedByWidget, _managedByWidgetMessage);
    final match = _matchOrReportFailure(route, onFailure: onFailure);
    if (match == null) {
      return null;
    }
    onMatch?.call(match);
    if (!_canStartAtOnce) {
      final turn = _takeTurn();
      await null;
      _endTurn(turn);
      if (_isDisposed) return null;
    }
    // No pause when every guard answers in its own call: the page is on the
    // stack as push returns.
    final answer = _canNavigate(match, onFailure: onFailure);
    final result = answer is ResolverResult ? answer : await answer;
    if (_isDisposed) return null;
    if (result.continueNavigation) {
      // Before [onAccepted]: when this page takes the place of the pages a
      // replaceAll replaces, as one its guard shows, they leave first, so a
      // redirect with replace finds none of them to replace and a rejection
      // brings back them all.
      _reportPageGoesOn();
      onAccepted?.call();
      _updateSharedPathData(
        queryParams: route.rawQueryParams,
        fragment: route.fragment,
        includeAncestors: true,
      );

      return await _addNewPage(
        result.route,
        notify: notify,
        index: insertAt,
        onFailure: onFailure,
      );
    }
    return null;
  }

  /// Removes last entry in stack and pushes given [route]
  /// if last entry == [route] page will just be updated
  ///
  /// The last entry is removed only once the guards of [route] let it
  /// through; a rejected [route] leaves the stack as it was.
  ///
  /// The code that opened the last entry gets `null` as it leaves. When
  /// [route] is that entry's own route, with other params or args, the screen
  /// stays and shows the new page, and that code goes on waiting for the
  /// result the screen closes with.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  @optionalTypeArgs
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findStackScope(route);
    return scope._push(
      route,
      onFailure: onFailure,
      onAccepted: scope._replacingTop(),
    );
  }

  // For replace and replacePath: takes the page now on top off, and marks the
  // url for replace, once the guards let the route that replaces it through.
  // Until then the page stays on the stack, so a rejected route leaves the
  // stack, the url and the wait of the code that opened the page as they were,
  // as a canceled replace navigation leaves the current entry and url on the
  // web, and Flutter's Navigator.pushReplacement takes the old route off in
  // the same step that pushes the new one.
  //
  // With [isHeldBack], for the redirect of a guard that a reevaluation asks:
  // the reevaluation puts the page back once its guards let it through, see
  // [_heldBackByReevaluation].
  VoidCallback _replacingTop({bool isHeldBack = false}) {
    final replaced = _pages.lastOrNull?.routeData;
    return () {
      // a guard may have removed it already, e.g. with redirectUntil(replace:
      // true)
      if (replaced != null &&
          _pages.any((page) => page.routeData == replaced)) {
        if (isHeldBack && _reevaluationsInProgress > 0) {
          _heldBackByReevaluation.add(replaced);
        }
        _markLeaving(
          _pages.where((page) => page.routeData == replaced),
          .replaced,
        );
        _takingOffForNewPage(
          () => _removeRoute(replaced._route, notify: false),
        );
      }
      markUrlStateForReplace();
    };
  }

  Future<T?> _redirect<T extends Object?>(
    PageRouteInfo route, {
    required void Function(StackRouter scope, RouteMatch<Object?> match)
    onMatch,
    OnNavigationFailure? onFailure,
    bool replace = false,
    bool isReevaluating = false,
  }) {
    final scope = _findStackScope(route);
    return scope._push(
      route,
      onFailure: onFailure,
      onMatch: (match) => onMatch(scope, match),
      // The page on top leaves only once the guards let [route] through, as
      // with replace: a [route] that doesn't open leaves it on the stack.
      onAccepted: replace
          ? scope._replacingTop(isHeldBack: isReevaluating)
          : null,
    );
  }

  /// Adds the corresponding pages to given [routes] list to the [_pages] stack
  /// at once
  ///
  /// The pages go on in one step, once the guards of every one of [routes]
  /// have let it through; until then the stack stays as it is. A guard that
  /// rejects one of [routes] rejects them all: the stack stays as it was.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  Future<void> pushAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
  }) {
    assert(routes.isNotEmpty, 'routes must not be empty.');
    final first = routes.firstOrNull;
    if (first == null) return Future.value();
    return _findStackScope(first)._pushAll(routes, onFailure: onFailure);
  }

  /// Pop the current route off the navigator and push all given [routes] in its
  /// place.
  ///
  /// Like [popAndPush], the pop is forced: it happens before the push, even
  /// when the current route is the only one in its router. A guard that
  /// rejects one of [routes] rejects them all, so only the pop stays.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  Future<void> popAndPushAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
  }) {
    assert(routes.isNotEmpty, 'routes must not be empty.');
    final first = routes.firstOrNull;
    if (first == null) return Future.value();
    final scope = _findStackScope(first)..pop();
    return scope._pushAll(routes, onFailure: onFailure);
  }

  /// Replaces every page of this stack with pages for [routes], the last one
  /// on top.
  ///
  /// With [updateExistingRoutes], a new page whose route is that of the page
  /// at its place, counted from the bottom of the stack or from the top, keeps
  /// that page's screen, as Flutter's Navigator updates a page's route in
  /// place; the screen on top is kept by the first new page of its route,
  /// wherever it goes. A kept screen keeps its state, its result type and the
  /// wait of the code that opened it, which gets the result the screen closes
  /// with, and its nested router shows the children the new page's route
  /// names, as a nested router built anew would, once every guard lets the
  /// batch in. The code that opened any other page gets `null` as the page
  /// leaves.
  /// With [updateExistingRoutes] false, every new page gets a screen of its
  /// own.
  ///
  /// The pages are replaced in one step, once the guards of every one of
  /// [routes] have let it through. While a guard decides the stack stays as
  /// it is, and a guard that rejects one of [routes] rejects them all: the
  /// stack stays as it was. A page that a guard shows before it answers,
  /// such as a login with [NavigationResolver.redirectUntil], takes the place
  /// of the pages as it goes on, and so does a page that goes on once the
  /// guard has returned without an answer, such as a login the app shows
  /// when the guard asks for a sign-in: back from that page shows none of
  /// them, and they come back only if the guard then rejects. They stay gone
  /// once the app replaces the guard's page with another one, with [replace]
  /// or another [replaceAll]. Until the guard answers, the code that opened
  /// one of them goes on waiting: it gets the page's result if the page came
  /// back, and `null` once the page is gone for good. A guard that shows no
  /// page keeps them until it answers.
  ///
  /// If [onFailure] is given, navigation errors are passed to it; otherwise
  /// they are thrown. A guard's rejection reaches it as a
  /// [RejectedByGuardFailure].
  Future<void> replaceAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool updateExistingRoutes = true,
  }) {
    final first = routes.firstOrNull;
    if (first == null) return Future.value();
    return _findStackScope(first)._replaceAll(
      routes,
      onFailure: onFailure,
      updateExistingRoutes: updateExistingRoutes,
    );
  }

  Future<void> _replaceAll(
    List<PageRouteInfo> routes, {
    required bool updateExistingRoutes,
    OnNavigationFailure? onFailure,
    bool isLink = false,
  }) async {
    final matches = _matchAllOrReportFailure(routes, onFailure: onFailure);
    if (matches != null) {
      await _replaceAllMatches(
        matches,
        updateExistingRoutes: updateExistingRoutes,
        onFailure: onFailure,
        isLink: isLink,
      );
    }
  }

  // Replaces every page with pages for [matches], once every guard has let
  // them through. While a guard decides, such as one that awaits a request,
  // the stack stays as it is on screen, as Flutter's Router keeps
  // building the current pages while its delegate waits and iOS swaps a
  // navigation stack in one step (setViewControllers): no blank screen, and
  // a guard that rejects one of [matches] rejects them all and leaves the
  // pages with their State and the waits of the code that opened them.
  //
  // The pages to replace stay until a page goes on the stack in their place.
  // That is one of [matches], or before that a page a guard shows while it
  // has not answered, such as a login it shows with redirectUntil, awaited or
  // not, or pushes itself: the pages leave in the step in which that page
  // goes on, not before, as while the guard's page waits for guards of its
  // own, and not after, so back from it never shows them, its leave report
  // names them as replaced, and a redirect with replace finds none of them
  // to replace. Android finishes the old screens of a task it clears as the
  // new one starts. A guard that shows no page, as one that asks in a dialog
  // or answers later from a callback, keeps them until it answers. They come
  // back only if the guard then rejects, and not once the app has replaced
  // the page that took their place with one of its own.
  //
  // Whose page it is matters only while the guard's call still runs, as
  // while it awaits a request: then only the guard's own page takes their
  // place, and a page the app pushes meanwhile goes on over them and is
  // replaced with them. Once the guard's call has returned without an
  // answer, the guard waits for something outside it, such as a sign-in the
  // app shows from a listener of the session or in a later frame: from then
  // on a page that goes on this stack takes their place, whoever puts it on,
  // and one that went on during the call does as the call returns.
  //
  // A link's replacement, [isLink], keeps the pages under a guard's page:
  // they are the user's own pages, which the link found open, so back from
  // the guard's page rejects the link and shows them, as back from a screen
  // a link opened shows the app under it on Android and iOS. Only the app's
  // own replaceAll, as after a sign-out, has them leave for the guard's page.
  //
  // The screens the new pages keep are told as the pages are replaced, from
  // the pages the navigator shows at that moment.
  Future<void> _replaceAllMatches(
    List<RouteMatch<Object?>> matches, {
    required bool updateExistingRoutes,
    OnNavigationFailure? onFailure,
    bool isLink = false,
  }) {
    // Let go once replaceAll has its answer, so the call that waits on the
    // last new page doesn't hold the pages that left.
    List<AutoRoutePage<Object?>>? pagesBefore = List.of(_pages);
    // The pages a guard that holds the navigation took the place of.
    var setAside = const <AutoRoutePage<Object?>>[];
    // The page that went on in their place, such as the guard's login page,
    // once it is on.
    RouteData<Object?>? placeTaker;
    // Whether the pages were set aside for a page that is going on next.
    var isPlaceOpen = false;
    // Whether a guard's call has returned without an answer, and the guard
    // has not answered since: it waits for something outside its call.
    var isGuardWaiting = false;
    // [_guardStateChanges] as the first pages were set aside, or null when
    // a reevaluation was asking about them then.
    int? changesAtSetAside;
    var isSetAside = false;
    // Sets the pages to replace aside for the page that goes on next in
    // their place, or with [isPageOn] for one that is on already.
    void setPagesAside({bool isPageOn = false}) {
      if (isLink) return;
      final leaving = [...?pagesBefore?.where(_pages.contains)];
      if (leaving.isEmpty) return;
      setAside = [...setAside, ...leaving];
      if (!isSetAside) {
        isSetAside = true;
        changesAtSetAside = _reevaluationsInProgress > 0
            ? null
            : root._guardStateChanges;
      }
      _setAsideByReplaceAll.addAll(leaving);
      // A page's nested router leaves with its screen. The pages it has
      // open are kept for the router the page gets if it comes back, which
      // opens them as a router built anew opens the pages its page names.
      for (final page in leaving) {
        final data = page.routeData;
        final inner = _innerControllerOfMatch(data.matchId);
        if (inner == null || inner.managedByWidget) continue;
        final open = inner._openMatches();
        data.pendingChildren
          ..clear()
          ..addAll(open);
      }
      _markLeaving(leaving, .replaced);
      _pages.removeWhere(leaving.contains);
      placeTaker ??= isPageOn ? _pages.firstOrNull?.routeData : null;
      isPlaceOpen = placeTaker == null;
      markUrlStateForReplace();
    }

    return _navigateAll(
      matches,
      onFailure: onFailure,
      replacement: _PagesReplacement(
        onGuardShowsPage: (router) {
          // A page on another router is not in their place.
          if (identical(router, this)) setPagesAside();
        },
        onGuardReturned: () {
          isGuardWaiting = true;
          // A page that went on during the guard's call, put on by code
          // that is not the guard's, such as a listener of the session the
          // guard asked: it is in their place as the call returns.
          final hasNewPage = _pages.any(
            (page) => !(pagesBefore?.contains(page) ?? true),
          );
          if (hasNewPage) setPagesAside(isPageOn: true);
        },
        onGuardAnswered: () => isGuardWaiting = false,
        onPageGoesOn: () {
          if (isGuardWaiting) setPagesAside();
        },
        onPageWentOn: (data) {
          if (!isPlaceOpen) return;
          placeTaker = data;
          isPlaceOpen = false;
        },
        onAllAccepted: (accepted) {
          pagesBefore = null;
          _setAsideByReplaceAll.removeAll(setAside);
          _completeFuturesOf(setAside);
          setAside = const [];
          isGuardWaiting = false;
          isPlaceOpen = false;
          placeTaker = null;
          final replacing = updateExistingRoutes
              ? _keepingScreensOf(List.of(_pages), accepted)
              : accepted;
          _markLeaving(_pages, .replaced);
          _pages.clear();
          // Also the pages a reevaluation holds off the stack for a guard
          // that has not answered: they are replaced with the rest.
          _heldBackByReevaluation.clear();
          if (!updateExistingRoutes) {
            _stackKey = UniqueKey();
          }
          markUrlStateForReplace();
          return replacing;
        },
        onRejected: () {
          pagesBefore = null;
          isGuardWaiting = false;
          if (setAside.isEmpty) return;
          _setAsideByReplaceAll.removeAll(setAside);
          // The app replaced the page that took their place, with replace
          // or another replaceAll, as a "continue as guest" button on a
          // guard's login page does: the guard's redirect ended with its
          // page, which rejects, but the new page took that page's place,
          // and with it the place of the pages set aside. They are gone for
          // good. A replace of another page, as of one the login page
          // opened, changes nothing for them.
          if (placeTaker?._isReplaced ?? false) {
            _completeFuturesOf(setAside);
            setAside = const [];
            return;
          }
          // A change of the state the guards read passed the pages by while
          // they were off the stack.
          final isChangePassedBy = changesAtSetAside != root._guardStateChanges;
          // Back as they were. Another replaceAll that had set them aside
          // for its own guard's page has put them back before this.
          for (final page in setAside) {
            final data = page.routeData.._isReplaced = false;
            // The pages its nested router opens again are asked as they go
            // in, as the pages on this stack are below.
            if (isChangePassedBy && data.hasPendingChildren) {
              final toAsk = _withGuardsToAsk(data.pendingChildren);
              data.pendingChildren
                ..clear()
                ..addAll(toAsk);
            }
          }
          // Under the pages put on meanwhile, such as a page the guard
          // still shows.
          _pages.insertAll(0, setAside);
          setAside = const [];
          markUrlStateForReplace();
          notifyAll(forceUrlRebuild: true);
          // A reevaluation asks only about pages on the stack, and drops
          // the answer of a guard whose page left meanwhile. They are asked
          // now, as a page that comes back into view after a sign-out is
          // checked again on iOS and Android.
          if (isChangePassedBy) unawaited(reevaluateGuards());
        },
      ),
    );
  }

  // [matches] and their children, with every guard still to be asked when
  // their pages are opened.
  static List<RouteMatch<Object?>> _withGuardsToAsk(
    List<RouteMatch<Object?>> matches,
  ) => [
    for (final match in matches)
      match.copyWith(
        evaluatedGuards: const [],
        children: switch (match.children) {
          final children? => _withGuardsToAsk(children),
          null => null,
        },
      ),
  ];

  // [matches], where each match the navigator will show in the route of a
  // page of [previous] has that page's match id. The navigator updates a
  // route with the new page of the same route at its place, counted from the
  // bottom of the stack and then from the top, as Flutter's Navigator updates
  // the routes of pages it can update from either end. The screen and its
  // state stay, so the new page takes over its result type, the wait of the
  // code that opened it and its nested router as it goes in, see
  // [_addNewPage]. The router shows the new page's children once the whole
  // batch is in, see [_openChildrenInKeptScreens]. The screen the navigator
  // shows on top is left to [_shownTopTakenOverBy].
  List<RouteMatch<Object?>> _keepingScreensOf(
    List<AutoRoutePage<Object?>> previous,
    List<RouteMatch<Object?>> matches,
  ) {
    final kept = List.of(matches);
    final shownTop = pagelessRoutesObserver.topPageRoute?.settings;
    // Whether the navigator shows the match at [index] in the route of
    // [page], as for a page of the same route in the same stack. If so, and
    // [page] isn't the screen on top, the match gets the page's match id.
    bool keepsScreen(AutoRoutePage<Object?>? page, int index) {
      final match = matches.elementAtOrNull(index);
      final data = page?.routeData;
      if (data == null ||
          match == null ||
          data.key != match.key ||
          data.stackKey != _stackKey) {
        return false;
      }
      if (page != shownTop) {
        kept[index] = match.withId(data.matchId);
        data._isKeptByReplaceAll = true;
      }
      return true;
    }

    var bottom = 0;
    while (keepsScreen(previous.elementAtOrNull(bottom), bottom)) {
      bottom++;
    }
    var previousTop = previous.length - 1;
    var matchesTop = matches.length - 1;
    while (previousTop >= bottom &&
        matchesTop >= bottom &&
        keepsScreen(previous.elementAtOrNull(previousTop), matchesTop)) {
      previousTop--;
      matchesTop--;
    }
    return kept;
  }

  /// Pop the whole stack except for the first entry
  ///
  /// Pages pushed earlier in the same turn, which the navigator has not built
  /// yet, leave as this is called, so a page pushed right after it stays. As
  /// a restored app starts, or while an earlier push waits for its guard, it
  /// waits for the navigator to build the pages, as [popUntil] does.
  void popUntilRoot() {
    final isAtRoot = _didPopUnbuiltPagesUntil(
      (route) => route.isFirst,
      keepsFirstPage: true,
    );
    if (isAtRoot) return;
    _whenPagesBuilt(isScoped: true, () {
      assert(
        _navigatorKey.currentState != null,
        'The navigator of this router is not mounted.',
      );
      _didPopUntilShowingNoneBetween((route) => route.isFirst);
    });
  }

  // Closes the pages on top that the navigator has not built yet, as the
  // pages pushed earlier in the same turn are, from the top down to the first
  // one [predicate] accepts, and answers whether it accepted one. They leave
  // as this is called, so a page pushed right after it stays: a pop that
  // waited for the frame that builds them would close that page with them,
  // and the navigator can't pop several routes it has only just built.
  // [predicate] is asked through a stand-in route, as pushAndPopUntil asks
  // it. With [keepsFirstPage] the first page stays and counts as accepted.
  //
  // Does nothing while an earlier push still waits for its turn, and when
  // the navigator still shows a page that has left the stack, as right after
  // a replaceAll: the callers then wait for the navigator, as before.
  bool _didPopUnbuiltPagesUntil(
    RoutePredicate predicate, {
    bool keepsFirstPage = false,
  }) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null ||
        _landingPushes.isNotEmpty ||
        !navigator.widget.pages.every(_pages.contains)) {
      return false;
    }
    final removed = <AutoRoutePage<Object?>>[];
    var isAccepted = false;
    while (!isAccepted) {
      final top = _pages.lastOrNull;
      if (top == null || navigator.widget.pages.contains(top)) break;
      isAccepted = keepsFirstPage && _pages.length == 1;
      if (!isAccepted) {
        final standIn = _UnshownPageRoute(top);
        isAccepted = predicate(standIn);
        standIn.release();
      }
      if (!isAccepted) {
        _removeRoute(top.routeData._route, notify: false);
        removed.add(top);
      }
    }
    if (removed.isNotEmpty) _notifyOfClosedUnbuilt(removed);
    return isAccepted;
  }

  // Runs [pop] once the navigators it walks have built every page, as a pop
  // that hands each [Route] to a predicate needs. Right after a push, or as
  // a restored app starts, before its first frame, the pages are on the
  // stack but no navigator has a route for them yet, so the pop would find
  // nothing to close and the pages would stay. It waits for the pushes
  // landing now, then for the frame that builds their pages, and pops after
  // that frame even if a page is still not built.
  void _whenPagesBuilt(
    VoidCallback pop, {
    required bool isScoped,
    bool isAfterFrame = false,
  }) {
    final routers = isScoped
        ? [this]
        : _topMostRouter()._buildRoutersHierarchy().whereType<StackRouter>();
    final landing = [for (final router in routers) ...router._landingPushes];
    if (landing.isNotEmpty) {
      unawaited(
        Future.wait(landing).then((_) {
          if (!_isDisposed) _whenPagesBuilt(pop, isScoped: isScoped);
        }),
      );
      return;
    }
    final isBuilt = routers.every((router) {
      final navigator = router._navigatorKey.currentState;
      return navigator != null &&
          router._pages.every(navigator.widget.pages.contains);
    });
    if (isBuilt || isAfterFrame) {
      pop();
      return;
    }
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!_isDisposed) {
          _whenPagesBuilt(pop, isScoped: isScoped, isAfterFrame: true);
        }
      })
      ..ensureVisualUpdate();
  }

  // Navigator.popUntil pops every route with its exit animation, so each
  // page in between shows while it leaves (flutter/flutter#59990). This
  // removes the routes in between first, while the top route still covers
  // them, then pops the top route with its animation over the route that
  // meets [predicate]. Returns whether a route met it.
  bool _didPopUntilShowingNoneBetween(RoutePredicate predicate) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    // The navigator's routes, top first: each page's route under the
    // pageless routes pushed over it, newest first.
    final routes = <Route<Object?>>[
      for (final page in _pages.reversed)
        if (pagelessRoutesObserver.routeOf(page) case final pageRoute?) ...[
          ...pagelessRoutesObserver.pagelessRoutesOver(pageRoute).reversed,
          pageRoute,
        ],
    ];
    final top = routes.firstOrNull;
    if (top == null || top != _topRouteOf(navigator)) {
      // A route the router doesn't know of is on top; pop as Flutter does.
      var wasMet = false;
      navigator.popUntil((route) => wasMet = predicate(route));
      return wasMet;
    }
    final target = routes.indexWhere(predicate);
    if (target == 0) return true;
    for (final route in routes.sublist(
      1,
      target == -1 ? routes.length : target,
    )) {
      final page = route.settings;
      // As a pop would, complete the page's push future first, while its
      // route is still known, then take the page off the stack, or the
      // navigator would build it again.
      if (page is AutoRoutePage) page.onPopInvoked(true, null);
      // A page added under a page still coming in, as two pushes in one
      // frame leave it, is not installed in the navigator yet, which can't
      // remove it; taking it off the stack drops it on the next build.
      if (route.navigator != null) navigator.removeRoute(route);
      if (page is AutoRoutePage) onPopPage(page);
    }
    // A pop may close the top route's own history first, such as an open
    // drawer, so pop until the route leaves, as Navigator.popUntil does.
    navigator.popUntil((route) => route != top);
    return target != -1;
  }

  // The top route of [navigator] that is not leaving: popUntil hands it to
  // the predicate first and stops as the predicate returns true.
  static Route<Object?>? _topRouteOf(NavigatorState navigator) {
    Route<Object?>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  /// Pop the current route off the navigator and push the given [route] in its
  /// place.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  @optionalTypeArgs
  Future<T?> popAndPush<T extends Object?, TO extends Object?>(
    PageRouteInfo route, {
    TO? result,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findStackScope(route)..pop<TO>(result);
    return scope._push(route, onFailure: onFailure);
  }

  /// Calls [removeRoute] repeatedly until the predicate returns true.
  ///
  /// Note: [removeRoute] does not respect PopScopes
  /// if [scoped] is set to true the predicate will
  /// visit all StackRouters in hierarchy starting from
  /// top until satisfied
  bool removeUntil(RouteDataPredicate predicate, {bool scoped = true}) {
    if (scoped) {
      return _removeUntil(predicate);
    }
    final routers = _topMostRouter()._buildRoutersHierarchy();
    var wasPredicateSatisfied = false;
    for (final router in routers.whereType<StackRouter>()) {
      router._removeUntil((route) {
        return wasPredicateSatisfied = predicate(route);
      });
      if (wasPredicateSatisfied) break;
    }
    return wasPredicateSatisfied;
  }

  /// Calls [maybePop] repeatedly on the navigator until the predicate returns
  /// true.
  ///
  /// see [Navigator.popUntil]
  ///
  /// if [scoped] is set to true the predicate will
  /// visit all StackRouters in hierarchy starting from
  /// top until satisfied
  ///
  /// Right after a push, or as a restored app starts, before its first
  /// frame, the navigator has no route yet for the pages it would close.
  /// Pages pushed earlier in the same turn leave as this is called, from the
  /// top down to the first one [predicate] accepts, so a page pushed right
  /// after it stays. [predicate] then gets a stand-in page route that has the
  /// page as its settings, so [ModalRoute.withName] finds the page. As a
  /// restored app starts, or while an earlier push waits for its turn, it
  /// waits for the navigator to build the pages, then pops.
  void popUntil(RoutePredicate predicate, {bool scoped = true}) {
    _popUntilFromUnbuiltDown(
      predicate,
      isScoped: scoped,
      keepsFirstPage: false,
      popBuilt: (walked) =>
          _popUntilNow(predicate, isScoped: scoped, walked: walked),
    );
  }

  // [popUntil] on the routes the navigators have now, for a caller that
  // pushes right after it, which a later pop would also close.
  void _popUntilNow(
    RoutePredicate predicate, {
    required bool isScoped,
    List<StackRouter>? walked,
  }) {
    if (isScoped) {
      _didPopUntilShowingNoneBetween(predicate);
      return;
    }
    final routers =
        walked ??
        _topMostRouter()._buildRoutersHierarchy().whereType<StackRouter>();
    for (final router in routers) {
      final navState = router._navigatorKey.currentState;
      if (navState == null) break;
      if (router._didPopUntilShowingNoneBetween(predicate)) break;
    }
  }

  // Like [popUntil], but the last navigator it walks keeps its first route,
  // so a predicate no route satisfies doesn't pop every page and leave the
  // screen blank. popUntil itself still pops them all, as clearing the stack
  // with `popUntil((_) => false)` relies on.
  void _popUntilKeepingFirstPage(
    RoutePredicate predicate, {
    required bool scoped,
    List<StackRouter>? walked,
  }) {
    if (scoped) {
      return _navigatorKey.currentState?.popUntil(
        (route) => predicate(route) || route.isFirst,
      );
    }
    final routers =
        walked ??
        _topMostRouter()
            ._buildRoutersHierarchy()
            .whereType<StackRouter>()
            .toList();
    var wasPredicateSatisfied = false;
    for (final router in routers) {
      final navState = router._navigatorKey.currentState;
      if (navState == null) break;
      final isLast = router == routers.last;
      navState.popUntil(
        (route) =>
            (wasPredicateSatisfied = predicate(route)) ||
            isLast && route.isFirst,
      );
      if (wasPredicateSatisfied) break;
    }
  }

  bool _removeUntil(RouteDataPredicate predicate, {bool notify = true}) {
    var didRemove = false;
    for (final candidate in List<AutoRoutePage<Object?>>.unmodifiable(
      _pages,
    ).reversed) {
      if (predicate(candidate.routeData)) {
        break;
      }
      _markRemovedByApp([candidate]);
      _removeLast(notify: false);
      didRemove = true;
    }
    if (didRemove && notify) {
      notifyAll(forceUrlRebuild: true);
    }
    return didRemove;
  }

  /// Removes any route that satisfied the [predicate].
  ///
  /// Note: [removeRoute] does not respect PopScopes
  ///
  /// Calls [notifyAll] once, after the last route is removed, if [notify] is
  /// true. With [notify] false no listener is told and the url stays as it
  /// was until the caller's next change notifies.
  bool removeWhere(RouteDataPredicate predicate, {bool notify = true}) {
    var didRemove = false;
    for (final entry in List<AutoRoutePage<Object?>>.unmodifiable(_pages)) {
      if (predicate(entry.routeData)) {
        didRemove = true;
        removeRoute(entry.routeData, notify: false);
      }
    }
    if (notify) {
      notifyAll(forceUrlRebuild: true);
    }
    return didRemove;
  }

  /// Replaces the list of [_pages] with given [routes] result
  /// used by declarative routing widgets
  void updateDeclarativeRoutes(List<PageRouteInfo> routes) {
    final matches = <RouteMatch<Object?>>[];
    for (final route in routes) {
      final match = _matchOrReportFailure(route);
      if (match == null) {
        break;
      }
      if (match.guards.isNotEmpty) {
        throw FlutterError('Declarative routes can not have guards');
      }
      matches.add(match);
    }
    final previous = List.of(_pages);
    _pages.clear();
    for (final match in _keepingDeclarativeScreensOf(previous, matches)) {
      final data = _createRouteData<Object?>(match, routeData);
      _pages.add(data.buildPage());
      // A kept screen keeps its nested router, which now reads its params
      // from the new page.
      for (final ctr in _childControllers) {
        if (ctr.matchId == data.matchId) ctr.updateRouteData(data);
      }
    }
    // The app's list builds new pages each time, so only pops are reported.
    _pagesAtLastLeaveReport = List.of(_pages);
    _leaveKinds.clear();

    navigationHistory.onNewUrlState(
      UrlState.fromSegments(
        root.currentSegments,
        shouldReplace: current == routeData,
      ),
      notify: false,
    );
  }

  // [matches], where each match the navigator will show in the route of a
  // page of [previous] has that page's match id, so the screen keeps its
  // nested router, which is found by match id. Flutter's Navigator updates
  // the route of a page in place when the new page at its place, counted
  // from the bottom of the stack and then from the top, is of the same route
  // (Page.canUpdate), and keeps the route's state.
  List<RouteMatch<Object?>> _keepingDeclarativeScreensOf(
    List<AutoRoutePage<Object?>> previous,
    List<RouteMatch<Object?>> matches,
  ) {
    final kept = List.of(matches);
    bool keepsScreen(int previousIndex, int index) {
      final data = previous.elementAtOrNull(previousIndex)?.routeData;
      final match = matches.elementAtOrNull(index);
      if (data == null || match == null || data.key != match.key) {
        return false;
      }
      kept[index] = match.withId(data.matchId);
      return true;
    }

    var bottom = 0;
    while (keepsScreen(bottom, bottom)) {
      bottom++;
    }
    var previousTop = previous.length - 1;
    var matchesTop = matches.length - 1;
    while (previousTop >= bottom &&
        matchesTop >= bottom &&
        keepsScreen(previousTop, matchesTop)) {
      previousTop--;
      matchesTop--;
    }
    return kept;
  }

  // async, so a match failure reaches the returned future, not the caller's
  // stack. Completes once every guard has decided, not when the last page is
  // popped.
  Future<void> _pushAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool notify = true,
  }) async {
    final matches = _matchAllOrReportFailure(routes, onFailure: onFailure);
    if (matches != null) {
      await _pushAllGuarded<void>(
        matches,
        onFailure: onFailure,
        notify: notify,
        returnLastRouteCompleter: false,
      );
    }
  }

  // Tells both, or the one given; null when neither is.
  static ValueChanged<StackRouter>? _bothTold(
    ValueChanged<StackRouter>? first,
    ValueChanged<StackRouter>? second,
  ) => (first == null || second == null)
      ? (first ?? second)
      : (router) {
          first(router);
          second(router);
        };

  @optionalTypeArgs
  Future<T?> _pushAllGuarded<T extends Object?>(
    List<RouteMatch<Object?>> routes, {
    OnNavigationFailure? onFailure,
    bool notify = true,
    bool updateAncestorsPathData = true,
    bool returnLastRouteCompleter = true,
    bool isReevaluating = false,
    bool goesInAtOnce = false,
    Completer<void>? pushed,
    ValueChanged<RouteMatch<Object?>>? onLastRouteAdded,
    VoidCallback? onFirstRouteAccepted,
    _PagesReplacement? replacement,
    int? link,
    ValueChanged<StackRouter>? onGuardShowsPage,
    // Where the last page goes, when not on top: a page reached again under
    // the pages above it, see [_popUntilOrPushAll].
    int? Function()? lastPageAt,
  }) async {
    assert(!managedByWidget, _managedByWidgetMessage);

    // A page popped since the stack was collected for reevaluation stays
    // closed, with the pages above it.
    bool wasPopped(RouteMatch<Object?> match) =>
        match is ReevaluatableRouteMatch &&
        match.currentPage.routeData._isPoppedByNavigator;
    // A reevaluation asks the guards of each page with the page where it is:
    // the stack stays as it is on screen while a guard's check runs, as
    // Flutter's Router keeps building the current pages while its delegate
    // waits, and as a sign-in check in flight leaves the screen up on iOS and
    // Android. Only the guard's answer closes a page, with the pages above
    // it, which the reevaluation has not asked yet. This takes off the pages
    // of the routes from the one at [index] up.
    List<AutoRoutePage<Object?>> takeOffPagesFrom(int index) {
      final leaving = {
        for (final route in routes.skip(index))
          if (route is ReevaluatableRouteMatch) route.currentPage.routeData,
      };
      final onStack = _pages
          .where((page) => leaving.contains(page.routeData))
          .toList();
      _pages.removeWhere(onStack.contains);
      _heldBackByReevaluation.addAll(onStack.map((page) => page.routeData));
      return onStack;
    }

    // Completed with null when the guard of a page this reevaluation asks
    // returns without an answer: from then on the reevaluation goes on
    // without that page and the pages above it, see [_awaitLetGoAnswer].
    final letGo = Completer<ResolverResult?>();
    var letGoPages = const <AutoRoutePage<Object?>>[];

    // A batch over pages already on screen, such as pushAll or a link with
    // the pages below its own, goes in as one step: the stack stays as it is
    // on screen until every guard has answered, and a guard that rejects a
    // route rejects the whole batch, with nothing to undo. Flutter's
    // Navigator takes a new list of pages as one update, Android applies a
    // fragment transaction as one atomic set of operations, and on the web a
    // canceled navigation leaves the url and the current entry as they were.
    // A batch that begins on an empty stack, as when the app starts at a
    // link, puts each page on as its guards accept and keeps those pages when
    // a later guard rejects: a page a guard shows meanwhile, such as a login,
    // has them under it, as Android keeps the screens it puts under a linked
    // screen. A reevaluation decides page by page.
    final isHeld = goesInAtOnce || (!isReevaluating && _pages.isNotEmpty);
    // The pages the routes before the last took off, such as a top page that
    // keeps no history: their callers wait until the batch ends; see
    // [_endWaitOfTakenOff].
    final takenOff = <AutoRoutePage<Object?>>[];
    // The link whose navigation runs this batch: handed down to a nested
    // router's batch, or the one the delegate starts in this call.
    final ofLink = isReevaluating ? null : (link ?? root._startingLink);
    // What the link that starts this batch does once its guards let it in.
    final onLinkAccepted = ofLink == null ? null : root._takeLinkStep(ofLink);
    // The page that takes over the screen on top opens its children in that
    // screen's nested router only once every page is in, as the screens
    // replaceAll keeps below the top do, see [_openChildrenInKeptScreens].
    final takeovers = <RouteData<Object?>>[];
    void openChildrenOfTakeovers() {
      for (final data in takeovers) {
        _openChildrenInTakenOverRouter(data, onFailure: onFailure);
      }
    }

    // Puts on the page of the route at [index], one before the last, which
    // its guards let through as [match].
    void putOn(int index, RouteMatch<Object?> match) {
      final pagesBefore = List.of(_pages);
      _takingOffForNewPage(() {
        if (index == 0) onFirstRouteAccepted?.call();
        if (match is ReevaluatableRouteMatch) {
          _addReevaluatedPage(match, notify: false);
        } else {
          unawaited(_addNewPage<T>(match, notify: false, takeovers: takeovers));
        }
      });
      final left = pagesBefore.whereNot(_pages.contains).toList();
      takenOff.addAll(left);
      _takenOffByOpenBatches.addAll(left);
    }

    // Puts on the page of the last route, which its guards let through as
    // [match], and tells the navigator. Returns the future of a new page,
    // which completes when the page closes, and null for a page that was
    // reevaluated.
    Future<T?>? putOnLast(RouteMatch<Object?> match) {
      if (routes.length == 1) onFirstRouteAccepted?.call();
      _updateSharedPathData(
        queryParams: match.queryParams.rawMap,
        fragment: match.fragment,
        includeAncestors: updateAncestorsPathData,
      );
      onLastRouteAdded?.call(match);
      if (match is ReevaluatableRouteMatch) {
        _addReevaluatedPage(match, notify: notify);
        openChildrenOfTakeovers();
        return null;
      }
      final popped = root._showingLink(
        () => _addNewPage<T>(match, notify: notify, index: lastPageAt?.call()),
        isLink: ofLink != null,
      );
      openChildrenOfTakeovers();
      if (pushed != null && !pushed.isCompleted) pushed.complete();
      return popped;
    }

    // In a batch that goes in as one step, the routes before the last that
    // the guards let through, which wait for the guards of the routes after
    // them.
    final held = <RouteMatch<Object?>>[];

    // A reevaluation takes no turn: it starts a microtask after the change
    // that asked for it, once its pages are collected, never inside a build.
    if (!isReevaluating && !_canStartAtOnce) {
      final turn = _takeTurn();
      await null;
      _endTurn(turn);
      if (_isDisposed) return null;
    }
    if (isReevaluating) _reevaluationsInProgress++;
    if (replacement != null) _openReplacements.add(replacement);
    try {
      for (var i = 0; i < routes.length; i++) {
        if (wasPopped(routes[i])) {
          takeOffPagesFrom(i + 1);
          break;
        }
        // Not asked: the page is no longer there to stay or to close.
        if (_wasTakenOffDuringReevaluation(routes[i])) continue;
        final answer = _canNavigate(
          routes[i],
          onFailure: onFailure,
          pendingRoutes: routes
              .whereIndexed((index, element) => index > i)
              .toList(),
          isReevaluating: isReevaluating,
          // A guard asked again that returns without an answer lets go of
          // its page: the page leaves the stack and the screen at once, with
          // the pages above it, and comes back once the guard lets it
          // through, see [_awaitLetGoAnswer]. The reevaluation goes on
          // without them. A guard that wants its page kept while it decides
          // awaits its answer inside its call. A page under what its guard
          // shows the user stays: under its redirect, see redirectUntil, or
          // a page or a dialog it puts on screen in its call, which Flutter's
          // Navigator would close with the page.
          //
          // A guard of replaceAll that returns without an answer waits for
          // something outside its call: from then on a page that goes on
          // takes the place of the pages to replace whoever puts it on, see
          // [_replaceAllMatches].
          onLeftUndecided: ({required isWaitingOnUser}) {
            if (!isReevaluating) {
              replacement?.onGuardReturned();
              return false;
            }
            if (isWaitingOnUser) return false;
            // A later guard of the same page returned without an answer too.
            if (letGo.isCompleted) return true;
            letGoPages = takeOffPagesFrom(i);
            // As a guard that closes its page: the page below takes its
            // history entry, and the pages heard they were removed.
            _markLeaving(letGoPages, .removed);
            markUrlStateForReplace();
            letGo.complete(null);
            return true;
          },
          // The page a guard of replaceAll shows itself takes their place
          // also while its call still runs; and a tab that waits for these
          // guards shows, so the user sees the page.
          onShowsPage: isReevaluating
              ? null
              : _bothTold(replacement?.onGuardShowsPage, onGuardShowsPage),
        );
        // No pause when every guard answers in its own call: the pages of a
        // batch the app calls are on the stack as the call returns, and a
        // reevaluation leaves no gap in which a page could be replaced
        // between its guard's answer and its place on the stack.
        // A reevaluation stops waiting once the guard lets go of its page.
        final waited = isReevaluating && answer is Future<ResolverResult>
            ? Future.any<ResolverResult?>([answer, letGo.future])
            : answer;
        final result = waited is Future<ResolverResult?>
            ? await waited
            : waited;
        if (result == null) {
          unawaited(
            _awaitLetGoAnswer(
              answer,
              letGoPages,
              routes.sublist(i + 1),
              onFailure: onFailure,
            ),
          );
          break;
        }
        replacement?.onGuardAnswered();
        if (_isDisposed) break;
        // A later link was let in while a guard decided. The pages this
        // link's guard set aside for its own page come back, unless a page
        // was replaced meanwhile, as when the later link replaced the stack.
        if (ofLink != null && root._isLinkOvertaken(ofLink)) {
          replacement?.onRejected();
          break;
        }
        final match = result.route;
        if (wasPopped(match)) {
          takeOffPagesFrom(i + 1);
          break;
        }
        // The app took the page off while its guard decided: the answer
        // comes too late to put it back, or to close the pages above it.
        if (_wasTakenOffDuringReevaluation(routes[i])) continue;
        if (result.continueNavigation) {
          final isLast = i == routes.length - 1;
          if (isHeld && !isLast) {
            held.add(match);
            continue;
          }
          if (isLast) {
            // The link that starts the batch is let in, before its pages go
            // on; or, when it goes on into the nested router of the page it
            // reaches again, once the guards there let it in; or, into the
            // nested router of a new page, built only with the page, once
            // the guards there let it in, see [_NestedLetIn].
            final hasChildren = match.children?.isNotEmpty ?? false;
            final isNestedRouterBuilt =
                _innerControllerOfMatch(match.id) != null;
            final waitsForNewRouter =
                hasChildren &&
                !isNestedRouterBuilt &&
                match is! ReevaluatableRouteMatch;
            if (onLinkAccepted != null && !waitsForNewRouter) {
              hasChildren && isNestedRouterBuilt
                  ? root._handLinkStepOn(ofLink!, onLinkAccepted)
                  : onLinkAccepted();
            }
            // With [replacement], the routes go on as it returns them, after
            // what it does to the stack.
            final accepted = [...held, match];
            final replaced = replacement == null
                ? const <AutoRoutePage<Object?>>[]
                : List.of(_pages);
            final going = replacement?.onAllAccepted(accepted) ?? accepted;
            _openReplacements.remove(replacement);
            // The pages replaceAll takes off answer their callers in this
            // step, once the new pages are on and it is known whose screen
            // and wait a new page took over, as Flutter's Navigator ends the
            // wait of every route that leaves its pages, whatever else is
            // pending. Not at the next report of leaves: a reevaluation
            // holds that report back until it ends, and one that waits
            // behind a guard's redirect page would wait for that page's
            // caller to be answered.
            takenOff.addAll(replaced);
            _takenOffByOpenBatches.addAll(replaced);
            final pagesBefore = waitsForNewRouter ? List.of(_pages) : null;
            going.take(going.length - 1).forEachIndexed(putOn);
            final popped = putOnLast(going.lastOrNull ?? match);
            if (pagesBefore != null) {
              _waitForNewNestedRouter(
                pagesBefore: pagesBefore,
                link: ofLink,
                linkStep: onLinkAccepted,
                onFailure: onFailure,
                // Pages this step took off can't come back.
                canTakeBack:
                    replacement == null && pagesBefore.every(_pages.contains),
              );
            }
            if (popped != null) {
              // Every guard let the batch through.
              _endWaitOfTakenOff(takenOff);
              // This is the last route, so the loop ends here either way.
              return returnLastRouteCompleter ? await popped : null;
            }
          } else {
            putOn(i, match);
          }

          if (isReevaluating && !result.reevaluateNext) {
            takeOffPagesFrom(i + 1);
            break;
          }
        } else {
          // A page its guard now closes leaves its history entry to the page
          // below, as a pop does; a new entry would lead back to the guard.
          if (match is ReevaluatableRouteMatch<Object?, Object?>) {
            _markLeaving([match.currentPage], .removed);
            final wasOnStack = _pages.remove(match.currentPage);
            takeOffPagesFrom(i + 1);
            if (wasOnStack) markUrlStateForReplace();
          } else if (replacement != null) {
            replacement.onRejected();
          } else if (held.isNotEmpty) {
            // The stack stays as it was. A link that brought the batch has
            // set its own url meanwhile: the url goes back to the page on
            // screen.
            markUrlStateForReplace();
            notifyAll(forceUrlRebuild: true);
          }
          break;
        }
      }
    } finally {
      _endWaitOfTakenOff(takenOff);
      _openReplacements.remove(replacement);
      if (isReevaluating && --_reevaluationsInProgress == 0) {
        // Not the pages whose guard let go of them: they wait for its answer.
        _heldBackByReevaluation.retainWhere(
          (data) =>
              _waitingForLetGoGuards.any((page) => page.routeData == data),
        );
      }
    }
    return null;
  }

  // The last page of a batch went on with pages named for its nested router,
  // which is built only with the page and asks its guards then, with its own
  // context. Until they let the navigation in, the step of its [link]
  // ([linkStep]) waits, so a link's dialog stays open, and so does what the
  // routers above do once let in; see [_NestedLetIn]. A guard's rejection
  // there reaches [onFailure], the caller's. A "no" there takes the
  // pages this step put on back, when [canTakeBack] and a page this router
  // had before stays under them: the root is never left empty, and a router
  // the navigation opened with this page alone keeps it, on its first page.
  void _waitForNewNestedRouter({
    required List<AutoRoutePage<Object?>> pagesBefore,
    required int? link,
    required VoidCallback? linkStep,
    required bool canTakeBack,
    OnNavigationFailure? onFailure,
  }) {
    final data = _pages.lastOrNull?.routeData;
    if (data == null ||
        !data.hasPendingChildren ||
        _innerControllerOfMatch(data.matchId) != null) {
      linkStep?.call();
      return;
    }
    final added = _pages.whereNot(pagesBefore.contains).toList();
    _NestedLetIn(
      root,
      link: link,
      linkStep: linkStep,
      onFailure: onFailure,
      takeBack: canTakeBack && pagesBefore.isNotEmpty
          ? () => _takeBack(added)
          : null,
    ).waitOn(data);
  }

  // Takes [pages], which a navigation put on, back off the stack once a
  // guard of a nested router turned that navigation down: the stack and the
  // url are as before it, in the same history entry, and their callers get
  // null. Returns false, and takes nothing, when none of them is on the
  // stack any longer, or when no page would be left.
  bool _takeBack(List<AutoRoutePage<Object?>> pages) {
    final onStack = pages.where(_pages.contains).toList();
    if (_isDisposed || onStack.isEmpty || onStack.length == _pages.length) {
      return false;
    }
    markUrlStateForReplace();
    for (final page in onStack.reversed) {
      removeRoute(page.routeData, notify: false);
    }
    notifyAll(forceUrlRebuild: true);
    return true;
  }

  // Waits for [answer], the answer of the guard that let go of the first of
  // [pages]: the pages a reevaluation took off the stack and the screen with
  // it, which went on without them, see [_pushAllGuarded]. A yes puts the
  // page back on top of the stack as it then is, as a page whose guard lets
  // it through goes on, and then asks the guards of [above], the routes of
  // the pages that were above it. A no leaves them off, and so does a yes
  // for a page the app took off meanwhile, as replaceAll does. The callers of
  // the pages that stay off hear null; the others go on waiting.
  Future<void> _awaitLetGoAnswer(
    FutureOr<ResolverResult> answer,
    List<AutoRoutePage<Object?>> pages,
    List<RouteMatch<Object?>> above, {
    OnNavigationFailure? onFailure,
  }) async {
    _waitingForLetGoGuards.addAll(pages);
    try {
      final result = await answer;
      final match = result.route;
      if (_isDisposed ||
          !result.continueNavigation ||
          match is! ReevaluatableRouteMatch<Object?, Object?> ||
          !_heldBackByReevaluation.contains(match.currentPage.routeData)) {
        return;
      }
      _addReevaluatedPage(match, notify: false);
      if (result.reevaluateNext && above.isNotEmpty) {
        await _pushAllGuarded<void>(
          above,
          onFailure: onFailure,
          notify: false,
          updateAncestorsPathData: false,
          isReevaluating: true,
        );
      }
    } finally {
      _waitingForLetGoGuards.removeAll(pages);
      _heldBackByReevaluation.removeWhere(
        (data) => pages.any((page) => page.routeData == data),
      );
      if (!_isDisposed) {
        final back = {for (final page in _pages) page.routeData};
        _completeFuturesOf(
          pages.where((page) => !back.contains(page.routeData)),
        );
        notifyAll();
      }
    }
  }

  // Runs [step], which takes pages off for a new page: the top page that
  // keeps no history, the page replace replaces, or all a route before a
  // batch's last takes off. They keep their callers waiting until the new
  // page is on, see [_takenOffForNewPage].
  void _takingOffForNewPage(VoidCallback step) {
    final wasTakingOff = _isTakingOffForNewPage;
    _isTakingOffForNewPage = true;
    try {
      step();
    } finally {
      _isTakingOffForNewPage = wasTakingOff;
    }
  }

  // Ends the wait of the callers of [pages], which a batch took off, once the
  // batch has ended. A page whose route data is back on the stack, as a
  // reevaluation builds it anew with new args, keeps its caller waiting, as
  // does one whose screen and wait a page on the stack took over, see
  // [_addNewPage]. The others left for good and answer null, as removed pages
  // do. Clears [pages], so the call that waits on the batch's last page
  // doesn't hold the pages that left.
  void _endWaitOfTakenOff(List<AutoRoutePage<Object?>> pages) {
    if (pages.isEmpty) return;
    _takenOffByOpenBatches.removeAll(pages);
    final stillOn = {for (final page in _pages) page.routeData};
    final shownWaits = _pendingPopCompletersOf(_pages);
    _completeFuturesOf(
      pages.where(
        (page) =>
            !stillOn.contains(page.routeData) &&
            !shownWaits.contains(page.routeData._popCompleter),
      ),
    );
    pages.clear();
  }

  void _addReevaluatedPage(
    ReevaluatableRouteMatch<Object?, Object?> match, {
    bool notify = true,
  }) {
    var page = match.currentPage;
    final data = page.routeData;
    // args a guard set are shown by a page built with them, which keeps the
    // route and its state
    if (match.args != data.args) {
      data._updateRoute(match.originalMatch);
      page = page.rebuild();
    }
    // the page may have been kept in the stack while a guard was redirecting
    final index = _pages.indexOf(match.currentPage);
    if (index == -1) {
      _pages.add(page);
    } else {
      _pages[index] = page;
    }
    if (notify) {
      notifyAll();
    }
  }

  // Adds a page for [route] on top, or at [index]. A page that takes over the
  // screen on top opens its children in that screen's nested router right
  // after. With [takeovers], the page's data goes there instead, for a batch
  // to open its children once the batch's last page is in: a guard later in
  // the batch could still keep the batch out, or take its time.
  Future<T?> _addNewPage<T extends Object?>(
    RouteMatch<Object?> route, {
    bool notify = true,
    int? index,
    OnNavigationFailure? onFailure,
    List<RouteData<Object?>>? takeovers,
  }) {
    // A page that goes on while a guard decides about a replaceAll may take
    // the place of the pages to replace, which leave first, see
    // [_replaceAllMatches].
    _reportPageGoesOn();
    final shownTop = _pages.lastOrNull?.routeData;
    // A top page that keeps no history leaves when a page goes on above it,
    // not when one goes in below it, as insert does: Flutter's Navigator
    // keeps the route on top when a page is added under it.
    final isAddedOnTop = index == null || index == _pages.length;
    if (isAddedOnTop && shownTop != null && !shownTop._route.keepHistory) {
      markUrlStateForReplace();
      _takingOffForNewPage(() => _removeRoute(shownTop._route, notify: false));
    }
    var match = route;
    final takenOver = index == null ? _shownTopTakenOverBy(route) : null;
    if (takenOver != null) {
      // The page takes over the route and the nested router of [takenOver], so
      // it keeps its match id, as navigate does, for the router to stay its
      // own.
      match = route.withId(takenOver.matchId);
    }
    // A page that takes over a screen the navigator shows, as a navigation to
    // that screen does, keeps the screen's result type: the navigator keeps
    // the screen's route, and casts its page to the route's type when it
    // closes. It also keeps the wait of the code that opened the screen,
    // which ends when the screen closes, as Flutter's Navigator keeps the
    // future of a route it keeps. And it keeps the screen's leave listeners,
    // which go on hearing the screen leave, as a PopScope in a route the
    // Navigator keeps goes on hearing its pops. Now, not once the navigator
    // shows the new page: a leave reported before then goes to this page.
    final screen = takenOver ?? _shownDataThatLeftWithId(match.id);
    // And the screen's nested router, which gets the page's data, see
    // [_createRouteData]. Marked only as the page goes in: a mark made before
    // stays if a guard keeps the page out, and the router would go to the
    // next page of the route, as it would to an earlier page of the route in
    // the same batch.
    if (screen != null) {
      for (final ctr in _childControllers) {
        if (ctr.matchId == screen.matchId) {
          ctr._isMarkedForDataUpdate = true;
        }
      }
    }
    final page = switch (screen) {
      null => _createRouteData<T>(
        match,
        routeData,
        popCompleter: Completer<T?>(),
      ).buildPage<T>(),
      final shown => shown._withResultType(
        <R>(data) => (_createRouteData<R>(
          match,
          routeData,
          popCompleter: data._pendingPopCompleter ?? Completer(),
        ).._leaveCallbacks = data._leaveCallbacks).buildPage<R>(),
      ),
    };
    final data = page.routeData;
    if (index != null && !isAddedOnTop) {
      _pages.insert(index, page);
    } else {
      _pages.add(page);
    }
    _reportPageWentOn(data);
    // The pages taken off for this page answer their callers, except one
    // whose screen and wait this page took over.
    _endWaitOfTakenOff(_takenOffForNewPage);
    if (notify) {
      notifyAll();
    }
    // After the notification, so the url this page makes keeps its own replace
    // mark and the nested router's url gets one of its own.
    if (takenOver != null) {
      if (takeovers == null) {
        _openChildrenInTakenOverRouter(data, onFailure: onFailure);
      } else {
        takeovers.add(data);
      }
    }
    return switch (data.popped) {
      final Future<T?> popped => popped,
      // The caller named a type the screen's result doesn't have.
      final popped => popped.then((result) => result is T ? result : null),
    };
  }

  // The data of the page with match [id] that the navigator shows, once it
  // has left the stack for a new page of its route to take its place, as
  // navigate takes off the page it reaches again.
  RouteData<Object?>? _shownDataThatLeftWithId(LocalKey id) {
    for (final page in _pagesAtLastLeaveReport.reversed) {
      if (page.routeData.matchId == id && !_pages.contains(page)) {
        return page.routeData;
      }
    }
    return null;
  }

  // The data of the page the navigator shows on top, once that page has left
  // the stack and [route] is about to go on top in its place. The new page
  // then takes over its route, see [AutoRoutePage.canUpdate], with the nested
  // router built inside it. A [route] that already has the page's match id,
  // as navigate gives it, comes with a caller that updates that router. A
  // [route] with the match id of another page that left takes over that
  // page's screen instead, as replaceAll gives it. A page the app removed
  // itself keeps its route (#1204), and so does one that replaceAll set
  // aside for a guard's page, which may come back.
  RouteData<Object?>? _shownTopTakenOverBy(RouteMatch<Object?> route) {
    final shownRoute = pagelessRoutesObserver.topPageRoute;
    final shownPage = shownRoute?.settings;
    if (shownRoute == null ||
        !shownRoute.isActive ||
        shownPage is! AutoRoutePage<Object?> ||
        shownPage.isRemoved ||
        _setAsideByReplaceAll.contains(shownPage) ||
        _pages.contains(shownPage)) {
      return null;
    }
    final data = shownPage.routeData;
    final doesTakeOver =
        data.key == route.key &&
        data.stackKey == _stackKey &&
        data.matchId != route.id &&
        _shownDataThatLeftWithId(route.id) == null;
    return doesTakeOver ? data : null;
  }

  // A fresh nested router opens the children of its page's route; the one a
  // page took over already shows the children of the page before, so it is
  // sent to the new ones, as if built anew. A route given no children comes
  // with its initial child, as with navigate; with no initial child either,
  // the router keeps the children it shows.
  void _openChildrenInTakenOverRouter(
    RouteData<Object?> data, {
    OnNavigationFailure? onFailure,
  }) {
    final inner = _innerControllerOfMatch(data.matchId);
    if (inner == null || !data.hasPendingChildren) return;
    final children = List<RouteMatch<Object?>>.unmodifiable(
      data.pendingChildren,
    );
    data.pendingChildren.clear();
    if (inner is StackRouter && !inner.managedByWidget) {
      unawaited(
        inner._replaceAllMatches(
          children,
          updateExistingRoutes: true,
          onFailure: onFailure,
        ),
      );
    } else {
      unawaited(inner._navigateAll(children, onFailure: onFailure));
    }
  }

  // The match ids of [routes] that keep a screen replaceAll keeps below the
  // top, see [_keepingScreensOf]. Takes the marks off those screens' pages,
  // so a batch a guard rejects leaves none behind.
  Set<LocalKey> _takeScreensKeptByReplaceAll(List<RouteMatch<Object?>> routes) {
    final kept = <LocalKey>{};
    for (final route in routes) {
      final data = _shownDataThatLeftWithId(route.id);
      if (data != null && data._isKeptByReplaceAll) {
        data._isKeptByReplaceAll = false;
        kept.add(route.id);
      }
    }
    return kept;
  }

  // Once every page of a batch is in, sends the nested router of each screen
  // it keeps below the top, by the match ids in [keptScreens], to the
  // children of the page that keeps it, as Flutter's Navigator builds the new
  // content of a page it updates in place, wherever it is in the stack. Not
  // before: a guard still deciding would see the screen change under it, and
  // one that rejects the batch would leave the screen on the new children.
  void _openChildrenInKeptScreens(
    Set<LocalKey> keptScreens, {
    OnNavigationFailure? onFailure,
  }) {
    final keeping = [
      for (final page in _pages)
        if (keptScreens.contains(page.routeData.matchId)) page.routeData,
    ];
    for (final data in keeping) {
      _openChildrenInTakenOverRouter(data, onFailure: onFailure);
    }
  }

  // Asks the guards of [route], one after another, whether it may open.
  // Answers at once when every guard answers in its own call, as one that
  // reads a flag and calls next does, so the caller can go on in the same
  // call, as the tabs router does with a tab's guards, see [_checkTabGuards].
  // From the first guard that returns without an answer, or awaits before it
  // gives one, it answers later.
  FutureOr<ResolverResult> _canNavigate(
    RouteMatch<Object?> route, {
    OnNavigationFailure? onFailure,
    List<RouteMatch<Object?>> pendingRoutes = const [],
    bool isReevaluating = false,
    _GuardHoldsCallback? onLeftUndecided,
    ValueChanged<StackRouter>? onShowsPage,
  }) {
    // Moves on as each guard is asked, at once or later.
    final guards = [...root.guards, ...route.guards].iterator;
    var routeToCheck = route;
    var shouldReevaluateNext = true;

    // Takes in the answer of [guard]. Returns it when it ends the check.
    ResolverResult? rejectionOf(ResolverResult result, AutoRouteGuard guard) {
      routeToCheck = result.route;
      if (!result.reevaluateNext) {
        shouldReevaluateNext = false;
      }
      if (result.continueNavigation) return null;
      if (onFailure != null) {
        onFailure(RejectedByGuardFailure(routeToCheck, guard));
      }
      return result;
    }

    // Asks [guard]. Returns its answer when that ends the check, and null
    // when it lets the route through.
    //
    // A guard whose answer is from before a change of the state the guards
    // are asked again for, see [reevaluateGuards], is asked once more before
    // its page goes in, so a sign-out that lands while a guard awaits a
    // request never opens the page it guards: the last change wins, as
    // Flutter's Router drops the answer of an older route parse when newer
    // route information arrives. Not for a change the guard makes itself,
    // and [timesLeft] times at most: a guard whose check changes that state
    // through code of the app, as one that refreshes a session the app
    // listens to, would be asked without end.
    FutureOr<ResolverResult?> ask(
      AutoRouteGuard guard, {
      int timesLeft = _kMaxAsksAgainInARow,
    }) {
      final resolver = NavigationResolver(
        this,
        Completer(),
        routeToCheck,
        pendingRoutes: pendingRoutes,
        isReevaluating: isReevaluating,
      );
      final guardEntry = GuardEntry(guard, resolver);
      activeGuardObserver._add(guardEntry);
      final checking = resolver._checkGuard(
        guard,
        this,
        onLeftUndecided: onLeftUndecided,
        onShowsPage: onShowsPage,
      );
      final answer = resolver._result;
      if (answer == null) {
        return checking
            // Also when the guard throws, as an async guard does when the
            // request it awaits fails: the navigation is over, so no guard
            // of it is in progress and no reevaluation asks it again.
            .whenComplete(() => activeGuardObserver._remove(guardEntry))
            .then((result) {
              // The stale answer is dropped whole, with the route it names.
              final isAskedAgain =
                  result.continueNavigation &&
                  resolver._isAnswerStale &&
                  timesLeft > 0 &&
                  !_isDisposed;
              return isAskedAgain
                  ? ask(guard, timesLeft: timesLeft - 1)
                  : rejectionOf(result, guard);
            });
      }
      // The guard answered in its own call: the navigation goes on now.
      // What the guard does after its answer no longer changes it; an
      // error it throws then is reported as any uncaught error is.
      unawaited(checking);
      activeGuardObserver._remove(guardEntry);
      return rejectionOf(answer, guard);
    }

    FutureOr<ResolverResult> askRest() {
      while (guards.moveNext()) {
        final guard = guards.current;
        if (routeToCheck.evaluatedGuards.contains(guard)) {
          routeToCheck = routeToCheck.copyWith(
            evaluatedGuards: List.from(
              routeToCheck.evaluatedGuards.where((e) => e != guard),
            ),
          );
          continue;
        }
        final rejection = ask(guard);
        if (rejection is Future<ResolverResult?>) {
          return rejection.then((result) => result ?? askRest());
        }
        if (rejection != null) return rejection;
      }
      return ResolverResult(
        continueNavigation: true,
        reevaluateNext: shouldReevaluateNext,
        route: routeToCheck,
      );
    }

    return askRest();
  }

  /// Preforms pop-until finds cosponsoring route with [routes].first
  /// then pushes all [routes]
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  Future<void> navigateAll(
    List<RouteMatch<Object?>> routes, {
    OnNavigationFailure? onFailure,
  }) {
    return _navigateAll(routes, onFailure: onFailure);
  }

  @override
  Future<T?> _navigateAll<T extends Object?>(
    List<RouteMatch<Object?>> routes, {
    OnNavigationFailure? onFailure,
    bool isReevaluating = false,
    bool keepsUnnamedPages = false,
    _PagesReplacement? replacement,
    int? link,
    VoidCallback? onLetIn,
    ValueChanged<StackRouter>? onGuardShowsPage,
  }) async {
    // A reevaluation closes the pages its guards reject, and a guard may show
    // a page of its own meanwhile, so the pages it closes are reported once
    // it ends.
    if (isReevaluating && _leaveReportHolds == 0) {
      return await _holdingLeaveReports(
        () =>
            _navigateAll<T>(routes, onFailure: onFailure, isReevaluating: true),
      );
    }
    // pages pushed after the stack was composed for reevaluation are not in
    // [routes]. A reevaluated page may be rebuilt, so it's known by its route
    // data
    final reevaluatedRoutes = {
      for (final route in routes)
        if (route is ReevaluatableRouteMatch) route.currentPage.routeData,
    };
    bool wasReevaluated(AutoRoutePage<Object?> page) =>
        reevaluatedRoutes.contains(page.routeData);
    // Here alone, so a navigation reports once however it reaches this router.
    if (managedByWidget) _onNavigate(routes);
    Future<T?>? popped;
    if (routes.isNotEmpty) {
      // What the navigation does once the guards of this router, and of the
      // nested router of the page it reaches, have let it in: [onLetIn], what
      // the router above does then, and closing the dialogs over that page.
      // A router the app's widgets manage asks no guard.
      var lettingIn = managedByWidget ? onLetIn : null;
      // Told when a guard of the nested router of that page shows a page of
      // its own while it decides.
      var onNestedGuardShowsPage = onGuardShowsPage;
      // Read in the call, before the first wait: the link the delegate is
      // starting is known only then.
      final ofLink = isReevaluating ? null : (link ?? root._startingLink);
      var mayUpdateRoute = routes.last;
      var keptScreens = _takeScreensKeptByReplaceAll(routes);
      if (!managedByWidget) {
        // The future of a pushed page completes when the page is popped, so
        // wait only until the page is added, to keep updating nested routers
        // right away.
        final pushed = Completer<void>();
        var isLastRouteAdded = false;
        // Takes off the pages above the page reached again, once its nested
        // router lets the navigation in, see [_popUntilOrPushAll].
        VoidCallback? takeOffPagesAbove;
        popped = _popUntilOrPushAll<T>(
          routes,
          onFailure: onFailure,
          isReevaluating: isReevaluating,
          pushed: pushed,
          onLastRouteAdded: (match) {
            // a guard may have overridden the route, e.g. its children
            mayUpdateRoute = match;
            isLastRouteAdded = true;
          },
          // The screens replaceAll keeps are known once its pages have left.
          replacement: replacement?.thenOnAllAccepted(
            (replacing) =>
                keptScreens = _takeScreensKeptByReplaceAll(replacing),
          ),
          link: ofLink,
          onGuardShowsPage: onGuardShowsPage,
          onPagesAboveHeld: (takeOff) => takeOffPagesAbove = takeOff,
        );
        // No pause when the last page went on in the call, as it does when
        // no guard makes the routes wait: the nested router or the tabs of
        // that page are reached in the same call, so a call made right after
        // this one acts on them as they then are. A reevaluation takes its
        // turns as before.
        if (isReevaluating || !pushed.isCompleted) {
          await Future.any([pushed.future, popped]);
        }
        if (!isReevaluating && !isLastRouteAdded) {
          // A guard rejected the routes, or a later link took over: the
          // nested router of a page they reach again keeps its children.
          return await popped;
        }
        if (isReevaluating) {
          // Pages pushed before or during the reevaluation stay on top of
          // the reevaluated ones, also of one a guard's redirect replaced
          // and the reevaluation put back.
          final pushedMeanwhile = _pages.whereNot(wasReevaluated).toList();
          _pages
            ..removeWhere((page) => !wasReevaluated(page))
            ..addAll(pushedMeanwhile);
          if (_pages.where(wasReevaluated).length < reevaluatedRoutes.length) {
            await _reopenInitialRoutesIfEmptied();
            // Nothing else tells the navigator of a nested router that its
            // guard closed the top page, as no page goes on in its place.
            if (!_isDisposed) notifyAll();
          }
        } else if (pushed.isCompleted) {
          final takeOff = takeOffPagesAbove;
          final reached = takeOff == null
              ? _pages.lastOrNull
              : _pages.lastWhereOrNull(
                  (page) => page.routeData.matchId == mayUpdateRoute.id,
                );
          lettingIn = () {
            takeOff?.call();
            _closePagelessRoutesOverTop(link: ofLink, over: reached);
            onLetIn?.call();
          };
          // A guard there that shows a page of its own, such as a sign-in
          // page, has the pages above taken off first, so the user sees it.
          if (takeOff != null) {
            onNestedGuardShowsPage = (router) {
              takeOff();
              onGuardShowsPage?.call(router);
            };
          }
          _openChildrenInKeptScreens(keptScreens, onFailure: onFailure);
        }
      }
      if (isReevaluating) {
        // The nested router of every page that stays, not only of the one on
        // top: a guarded page in the nested router of a page another page
        // covers is asked again too, and so is a guarded tab, or it would
        // show once the user goes back. One router after another, from the
        // bottom of the stack up, as a stack asks its own pages: a guard is
        // asked once the one before it has answered, so two guards that send
        // the user to a login page show one login page, not two.
        for (final route in routes) {
          // Also before the first: the router may have left while a guard
          // of its own pages decided.
          if (_isDisposed) break;
          await _reevaluateInside(
            route == routes.lastOrNull ? mayUpdateRoute : route,
            onFailure: onFailure,
          );
        }
        return await popped;
      }
      final mayUpdateController = _topInnerControllerOf(mayUpdateRoute.key);
      final newChildren = mayUpdateRoute.children ?? const [];
      // A page that took over this nested router has opened its children in
      // it; opening them again would stack them twice.
      if (newChildren.isNotEmpty &&
          (keptScreens.contains(mayUpdateRoute.id) ||
              _shownTopTakenOverBy(mayUpdateRoute) != null)) {
        lettingIn?.call();
        return null;
      }
      // The dialogs over a page whose nested router or tabs are asked next
      // close only once their guards let the navigation in, as a refused
      // navigation changes nothing; a link's do already. A nested router not
      // built yet asks its guards only once its page is in.
      if (mayUpdateController != null && newChildren.isNotEmpty) {
        return await mayUpdateController._navigateAll(
          newChildren,
          onFailure: onFailure,
          keepsUnnamedPages: keepsUnnamedPages,
          link: ofLink,
          onLetIn: lettingIn,
          onGuardShowsPage: onNestedGuardShowsPage,
        );
      }
      // A new page whose nested router, built with the page, asks its guards
      // only then: the navigation is let in once they let it in.
      final waiting = mayUpdateController == null && newChildren.isNotEmpty
          ? _NestedLetIn.waitingOn(
              _pages
                  .lastWhereOrNull(
                    (page) => page.routeData.matchId == mayUpdateRoute.id,
                  )
                  ?.routeData,
            )
          : null;
      if (waiting != null && lettingIn != null) {
        waiting.addLetIn(lettingIn);
      } else {
        lettingIn?.call();
      }
      if (mayUpdateController != null) {
        return await mayUpdateController._navigateAll(
          newChildren,
          onFailure: onFailure,
          keepsUnnamedPages: keepsUnnamedPages,
          link: ofLink,
        );
      }
    } else if (!managedByWidget && !keepsUnnamedPages) {
      // A path, a link, a history entry and a reevaluation name every page
      // this router shows, so with none it shows none. The listeners hear of
      // it, so the url no longer names a page that left. Not after navigate to
      // a route object that was given no children and has no initial child,
      // which names no pages for this router: its pages stay, as going back to
      // an open screen shows it as it was (iOS popToViewController, Android
      // popUpTo, Flutter's Navigator.popUntil).
      final hadPages = _pages.isNotEmpty;
      _reset();
      if (hadPages && !isReevaluating) notifyAll(forceUrlRebuild: true);
    }
    return await popped;
  }

  // Asks the guards of the pages in the nested router of the page [route]
  // reevaluated, if that page is still on the stack and holds a router.
  Future<void>? _reevaluateInside(
    RouteMatch<Object?> route, {
    OnNavigationFailure? onFailure,
  }) {
    if (!_pages.any((page) => page.routeData.matchId == route.id)) return null;
    final children = route.children ?? const [];
    // children a guard set while reevaluating are new routes, not pages
    // being reevaluated
    final areChildrenOverridden = children.any(
      (child) => child is! ReevaluatableRouteMatch,
    );
    return _innerControllerOfMatch(route.id)?._navigateAll(
      children,
      onFailure: onFailure,
      isReevaluating: !areChildrenOverridden,
    );
  }

  // A nested router its guards emptied, such as one a link opened on a guarded
  // child alone, shows its first page again instead of nothing.
  Future<void> _reopenInitialRoutesIfEmptied() async {
    if (_pages.isNotEmpty || isRoot || _isDisposed) return;
    final initialRoutes = matcher.match('');
    if (initialRoutes == null) return;
    await _pushAllGuarded(initialRoutes, returnLastRouteCompleter: false);
  }

  void _reset() {
    _markLeaving(_pages, .removed);
    _pages.clear();
    _childControllers.clear();
  }

  // After navigate or replaceAll lands on a page the navigator already shows,
  // that page is updated in place, so the routes pushed over it with
  // Navigator.push, such as dialogs, would stay on screen. They close: those
  // on top are popped, those under pages leaving now are removed unseen.
  // A guard reevaluation keeps them, since a guard may be showing one.
  //
  // [over] is the page the navigation reached, when the closing waits for
  // the guards of its nested router: it closes only the routes over that
  // page, and none once another page is on top, such as one the app pushed
  // while those guards decided, with a dialog of its own.
  void _closePagelessRoutesOverTop({int? link, AutoRoutePage<Object?>? over}) {
    // A link that goes on into a nested router closes them once let in.
    if (link != null &&
        root._deferToLinkAccepted(
          link,
          () => _closePagelessRoutesOverTop(over: over),
        )) {
      return;
    }
    final top = _pages.lastOrNull;
    if (top == null || (over != null && !identical(top, over))) return;
    final shownRoute = pagelessRoutesObserver.routeWhere(
      (route) =>
          route.settings is AutoRoutePage &&
          top.canUpdate(route.settings as Page<Object?>),
    );
    if (shownRoute == null) return;
    final pageless = pagelessRoutesObserver.pagelessRoutesOver(shownRoute);
    final navigator = shownRoute.navigator;
    if (pageless.isEmpty || navigator == null) return;
    if (pageless.contains(pagelessRoutesObserver.current)) {
      navigator.popUntil((route) => route == shownRoute);
    } else {
      pageless.forEach(navigator.removeRoute);
    }
  }

  /// Pushes the given [route] and removes the routes below it until the
  /// [predicate] returns true, as [Navigator.pushAndRemoveUntil] does.
  ///
  /// The [predicate] is asked about the routes from the top down, dialogs
  /// and other pageless routes included. The routes it rejects are removed,
  /// not popped, so they never show while [route] slides in: navigator
  /// observers hear [NavigatorObserver.didRemove] for them, their PopScope
  /// is not asked, and their push futures complete with null. They are
  /// removed only once the guards of [route] let it through; a rejected
  /// [route] leaves the stack as it was.
  ///
  /// if [scopedPopUntil] is false the [predicate] visits all StackRouters
  /// in hierarchy starting from the top-most one until satisfied. The routes
  /// it rejects in a nested router are removed the same way, and a nested
  /// router whose own page is removed keeps its pages on screen under
  /// [route] until it goes.
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  @optionalTypeArgs
  Future<T?> pushAndPopUntil<T extends Object?>(
    PageRouteInfo route, {
    required RoutePredicate predicate,
    bool scopedPopUntil = true,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findStackScope(route);
    return scope._push(
      route,
      onFailure: onFailure,
      onAccepted: () {
        if (scopedPopUntil) {
          scope._removePagesUntil(
            scope._rejectedPagesUntil(predicate).rejected,
            isForPush: true,
          );
          return;
        }
        // The predicate is asked about every router first, so a nested
        // router whose own page goes too is left as it is: its top page stays
        // under [route] while it slides in, as the scope's old top does.
        final routers = _topMostRouter()
            ._buildRoutersHierarchy()
            .whereType<StackRouter>()
            .toList();
        final rejectedPages = <int>[];
        for (final router in routers) {
          final (:isAccepted, :rejected) = router._rejectedPagesUntil(
            predicate,
          );
          rejectedPages.add(rejected);
          if (isAccepted) break;
        }
        // Each router sits on the top page of the next one.
        var isStillShown = true;
        for (var i = rejectedPages.length - 1; i >= 0; i--) {
          final router = routers.elementAtOrNull(i);
          final rejected = rejectedPages.elementAtOrNull(i);
          if (router == null || rejected == null) continue;
          if (isStillShown) {
            router._removePagesUntil(rejected, isForPush: router == scope);
          }
          isStillShown = isStillShown && rejected == 0;
        }
      },
    );
  }

  // Asks [predicate] about the routes from the top down until it accepts one.
  // Pageless routes it rejects, such as dialogs, are removed on the way; the
  // pages it rejects are only counted, for [_removePagesUntil].
  ({bool isAccepted, int rejected}) _rejectedPagesUntil(
    RoutePredicate predicate,
  ) {
    // Pageless routes, such as dialogs, sit above the top page.
    while (hasPagelessTopRoute) {
      final top = pagelessRoutesObserver.current!;
      if (predicate(top)) return (isAccepted: true, rejected: 0);
      final navigator = top.navigator;
      navigator?.removeRoute(top);
      if (pagelessRoutesObserver.current == top) break;
    }
    var rejected = 0;
    for (final page in _pages.reversed) {
      final shownRoute = pagelessRoutesObserver.routeOf(page);
      final bool isAccepted;
      if (shownRoute != null) {
        isAccepted = predicate(shownRoute);
      } else {
        // a page pushed in this frame has no route yet
        final unshownRoute = _UnshownPageRoute(page);
        isAccepted = predicate(unshownRoute);
        unshownRoute.release();
      }
      if (isAccepted) return (isAccepted: true, rejected: rejected);
      rejected++;
    }
    return (isAccepted: false, rejected: rejected);
  }

  // Removes the [count] top pages without animating them out. With [isForPush]
  // a page pushed in the same update makes the navigator remove them and keep
  // the old top under the new page; otherwise each is removed from the
  // navigator here, and this router is notified.
  void _removePagesUntil(int count, {required bool isForPush}) {
    _markLeaving(_pages.reversed.take(count), isForPush ? .replaced : .removed);
    for (var i = 0; i < count; i++) {
      final top = _pages.lastOrNull;
      if (top == null) break;
      final shownRoute = pagelessRoutesObserver.routeOf(top);
      if (!isForPush && shownRoute != null) {
        final shownNavigator = shownRoute.navigator;
        shownNavigator?.removeRoute(shownRoute);
      }
      _removeLast(notify: false);
      if (shownRoute != null) {
        // drops the removed page's history entry, as a pop does
        navigationHistory.rebuildUrlAfterPop();
      } else {
        // the browser never showed its url; the next page takes its entry
        markUrlStateForReplace();
      }
    }
    if (!isForPush && count > 0) {
      notifyAll(forceUrlRebuild: true);
    }
  }

  /// Removes last entry in stack and pushes given [path]
  /// if last entry.path == [path] page will just be updated
  ///
  /// The last entry is removed only once the guards of the first route [path]
  /// opens let it through; a rejected route leaves the stack as it was.
  ///
  /// if [includePrefixMatches] is true prefixed-matches
  /// will be added to to target destination
  /// see [RouteMatcher.matchUri]
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  @optionalTypeArgs
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findPathScopeOrReportFailure<StackRouter>(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
    if (scope != null) {
      final router = scope.router;
      return router._pushAllGuarded(
        scope.matches,
        onFailure: onFailure,
        onFirstRouteAccepted: router._replacingTop(),
      );
    }
    return SynchronousFuture(null);
  }

  /// Adds corresponding page to given [path] to [_pages] stack
  ///
  /// if [includePrefixMatches] is true prefixed-matches
  /// will be added to to target destination
  /// see [RouteMatcher.matchUri]
  ///
  /// if [onFailure] callback is provided, navigation errors will be passed to
  /// it otherwise they'll be thrown
  @optionalTypeArgs
  Future<T?> pushPath<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findPathScopeOrReportFailure<StackRouter>(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
    if (scope != null) {
      return scope.router._pushAllGuarded(scope.matches, onFailure: onFailure);
    }
    return SynchronousFuture(null);
  }

  /// Helper to pop all routes until route with [name] is found
  /// see [popUntil]
  ///
  /// When no route has [name], it pops down to the first page and keeps it,
  /// instead of leaving no page.
  void popUntilRouteWithName(String name, {bool scoped = true}) {
    final hasName = ModalRoute.withName(name);
    _popUntilFromUnbuiltDown(
      hasName,
      isScoped: scoped,
      keepsFirstPage: true,
      popBuilt: (walked) =>
          _popUntilKeepingFirstPage(hasName, scoped: scoped, walked: walked),
    );
  }

  /// Helper to pop all routes until route with [path] is found
  /// see [popUntil]
  ///
  /// When no route has [path], it pops down to the first page and keeps it,
  /// instead of leaving no page.
  void popUntilRouteWithPath(String path, {bool scoped = true}) {
    bool hasPath(Route<Object?> route) {
      if (route.settings is AutoRoutePage) {
        return (route.settings as AutoRoutePage).routeData.match == path;
      }
      // Assuming pageless routes are either dialogs or bottomSheetModals
      // and the user set a path as in RouteSettings(name: path) when
      // showing them
      return route.settings.name == path;
    }

    _popUntilFromUnbuiltDown(
      hasPath,
      isScoped: scoped,
      keepsFirstPage: true,
      popBuilt: (walked) =>
          _popUntilKeepingFirstPage(hasPath, scoped: scoped, walked: walked),
    );
  }
}

/// An Implementation of StackRouter used by nested
/// [AutoRouter] widgets
class NestedStackRouter extends StackRouter {
  /// Default constructor
  new({
    required RouteCollection routeCollection,
    required super.key,
    required super.matchId,
    required RouteData<Object?> routeData,
    required RoutingController super.parent,
    this.managedByWidget = false,
    super.onNavigate,
    super.navigatorKey,
  }) : _routeCollection = routeCollection,
       _matcher = RouteMatcher(routeCollection),
       _routeData = routeData {
    // When a widget above AutoRouter builds it anew, such as in another place
    // of its page when a two-pane layout becomes one pane, the new router is
    // created before the outgoing one of the same page is disposed, so it
    // opens the pages the outgoing router has open.
    final outgoing = _parent?._innerControllerOfMatch(matchId);
    if (!managedByWidget &&
        !routeData.hasPendingChildren &&
        outgoing is NestedStackRouter &&
        !outgoing.managedByWidget) {
      routeData.pendingChildren.addAll(outgoing._openMatches());
    }
  }
  RouteCollection _routeCollection;
  RouteMatcher _matcher;

  @override
  RouteCollection get routeCollection => _routeCollection;

  @override
  RouteMatcher get matcher => _matcher;

  @override
  void _reassemble() {
    if (_parent?._reassembledSubCollection(_routeData.name)
        case final collection?) {
      _routeCollection = collection;
      _matcher = RouteMatcher(collection);
    }
    super._reassemble();
  }

  @override
  final bool managedByWidget;

  RouteData<Object?> _routeData;

  @override
  RouteData<Object?> get routeData => _routeData;

  @override
  void updateRouteData(RouteData<Object?> data) {
    _routeData = data;
    for (final page in _pages) {
      page.routeData._parent = data;
    }
  }

  /// Adds the initial routes to the stack right away, so the first page of
  /// this router is part of the frame that builds it.
  ///
  /// This lets a [Hero] on the page that opened this router's page fly to a
  /// [Hero] on its first page: Flutter starts the flight right after the frame
  /// of the push, and looks for the destination [Hero] in what is built then.
  ///
  /// Returns false and adds nothing when the routes have to wait for
  /// [setupInitialRoutes], which runs guards with a context.
  @internal
  bool setupInitialRoutesSynchronously() {
    _nestedLetIn ??= _NestedLetIn.claim(_routeData);
    if (managedByWidget || root.guards.isNotEmpty) {
      return false;
    }
    final hasPendingChildren = _routeData.hasPendingChildren;
    final initialRoutes = hasPendingChildren
        ? List<RouteMatch<Object?>>.unmodifiable(_routeData.pendingChildren)
        : matcher.match('');
    final top = initialRoutes?.lastOrNull;
    if (initialRoutes == null ||
        top == null ||
        initialRoutes.any((route) => route.guards.isNotEmpty)) {
      return false;
    }
    for (final route in initialRoutes) {
      unawaited(_addNewPage(route, notify: false));
    }
    _updateSharedPathData(
      queryParams: top.queryParams.rawMap,
      fragment: top.fragment,
      includeAncestors: true,
    );
    if (hasPendingChildren) {
      _routeData.pendingChildren.clear();
    }
    _reportPagesUnderFirstPages(initialRoutes.length);
    // No guard here can turn the navigation down; one of a router this
    // router's last page builds still can.
    _letInOrHandOn(_takeNestedLetIn());
    return true;
  }

  // What the navigation that named this router's first pages does once the
  // guards here let it in, see [_NestedLetIn]: claimed as the router is
  // built, before the end of the frame that builds it.
  _NestedLetIn? _nestedLetIn;

  _NestedLetIn? _takeNestedLetIn() {
    final letIn = _nestedLetIn ?? _NestedLetIn.claim(_routeData);
    _nestedLetIn = null;
    return letIn;
  }

  // The pages named for this router are on: [letIn] waits for the nested
  // router of the last of them instead, when that page went on with pages
  // of its own for a router not built yet; otherwise the navigation is let
  // in, after the frame, as this may run while widgets build.
  void _letInOrHandOn(_NestedLetIn? letIn) {
    if (letIn == null) return;
    final inner = _NestedLetIn.waitingOn(_pages.lastOrNull?.routeData);
    if (inner != null) {
      letIn.handOnTo(inner);
    } else if (_pages.lastOrNull?.routeData case final last?
        when last.hasPendingChildren &&
            _innerControllerOfMatch(last.matchId) == null) {
      letIn.waitOn(last);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => letIn.letIn());
    }
  }

  // The first [count] pages of this router went on together, after the url
  // that names the last of them was reported: the url itself is the same,
  // and nobody hears of the pages under it. A web history that writes the
  // browser gives each its entry from the url state of the pages on, once
  // they are, so the url is reported again then.
  void _reportPagesUnderFirstPages(int count) {
    if (count < 2 || !navigationHistory.writesBrowser) return;
    scheduleMicrotask(() {
      if (!_isDisposed) navigationHistory.rebuildUrl();
    });
  }

  // Opens [routes], the pages a link or a navigation named for this router
  // before it was built. When a guard keeps the last of them out, the router
  // shows the pages below it that were let in, or, with none, the page it
  // opens with when it is named no pages, its first: a nested router is
  // never left blank where it has a page to show, as it isn't when a
  // reevaluation empties it, see [_reopenInitialRoutesIfEmptied], and
  // Flutter's Navigator takes no empty list of pages. The navigator is told,
  // since the pages below went on without a word, and the url, which named
  // the page that was kept out, names the page on screen, in the same
  // history entry: on the web a canceled navigation leaves the url of the
  // document on screen.
  //
  // While a guard of a later page decides, the pages before it that went on,
  // such as the page a link brings below its own, show: a page on the stack
  // is a page on screen, as Flutter's Navigator shows the pages its list
  // holds. The url is left to the answer. A router that is named one page
  // alone has none to show meanwhile and shows its placeholder.
  //
  // The navigation that named them, [letIn], is let in once the last page is
  // on. A "no" takes back the page this router is in, see [_NestedLetIn],
  // unless a later navigation reached that page or this router meanwhile.
  Future<void> _openPendingRoutes(
    List<RouteMatch<Object?>> routes, {
    _NestedLetIn? letIn,
  }) async {
    var isLastPageOn = false;
    final dataBefore = _routeData;
    await _pushAllGuarded(
      routes,
      returnLastRouteCompleter: false,
      onFailure: letIn?.onFailure,
      onLastRouteAdded: (_) {
        isLastPageOn = true;
        _reportPagesUnderFirstPages(routes.length);
      },
      // The batch goes on without a pause until a guard makes it wait. So
      // when its last page is not on a microtask after its first, a guard is
      // deciding, or has kept a page out, and nobody has told the navigator
      // of the pages that went on.
      onFirstRouteAccepted: () => scheduleMicrotask(() {
        if (!isLastPageOn && !_isDisposed) notifyListeners();
      }),
    );
    if (isLastPageOn) {
      if (!_isDisposed) _letInOrHandOn(letIn);
      return;
    }
    if (_isDisposed) return;
    // A later navigation that reached this router's page, or put a page of
    // its own here, keeps the page.
    final ownIds = {for (final route in routes) route.id};
    final isReachedSince =
        !identical(_routeData, dataBefore) ||
        _pages.any((page) => !ownIds.contains(page.routeData.matchId));
    if (letIn?.turnDown(canTakeBack: !isReachedSince) ?? false) return;
    // The pages kept out are the ones this router opens with, as when its
    // first page is the guarded one: it has no other page to show, and its
    // guard is not asked a second time.
    final first = matcher.match('');
    final isFirstPageKeptOut =
        first != null &&
        const ListEquality<String>().equals(
          [for (final route in first) route.name],
          [for (final route in routes) route.name],
        );
    if (isFirstPageKeptOut) return;
    // Before the first page goes on, whose url would else be a new entry
    // after the one of the page that was kept out.
    markUrlStateForReplace();
    await _reopenInitialRoutesIfEmptied();
    if (!_isDisposed) notifyAll(forceUrlRebuild: true);
  }

  @internal
  /// Pushes the initial routes to the stack.
  ///
  /// A router built by `AutoRouter.declarative` pushes nothing: it hands the
  /// routes a link opened to [pendingRoutesHandler] for its routes callback.
  void setupInitialRoutes() {
    final letIn = _takeNestedLetIn();
    if (_routeData.hasPendingChildren) {
      final initialRoutes = List<RouteMatch<Object?>>.unmodifiable(
        _routeData.pendingChildren,
      );
      if (managedByWidget) {
        pendingRoutesHandler._initialPendingRoutes = initialRoutes
            .map((e) => e.toPageRouteInfo())
            .toList();
        // The app's routes callback asks no guard.
        _letInOrHandOn(letIn);
      } else {
        unawaited(_openPendingRoutes(initialRoutes, letIn: letIn));
      }
      _routeData.pendingChildren.clear();
    } else if (!managedByWidget) {
      _letInOrHandOn(letIn);
      final possibleInitialRoutes = matcher.match('');
      if (possibleInitialRoutes != null) {
        unawaited(
          _pushAllGuarded(
            possibleInitialRoutes,
            returnLastRouteCompleter: false,
          ),
        );
      }
    }
  }
}

// What a navigation does once the guards of the nested router of a page it
// put on let it in. That router is built only with the page and asks its
// guards then, with its own context, so the page shows first. Until they
// answer, the step of the navigation's link waits, so a link's dialog stays
// open, and so does what the routers above do once let in, such as closing
// the dialogs over their page. A "no" there takes the page back, as
// Android's conditional navigation pops back from a destination whose check
// fails, and as on the web a canceled navigation leaves the document on
// screen.
class _NestedLetIn {
  new(this._root, {this.link, this.linkStep, this.takeBack, this.onFailure});

  // The navigation waiting on the nested router of the page of a route data,
  // until that router claims it.
  static final _ofPage = Expando<_NestedLetIn>();

  final RootStackRouter _root;

  // The link whose navigation this is, if any.
  int? link;

  // What the link does once let in, see [RootStackRouter._openLink].
  VoidCallback? linkStep;
  VoidCallback? _onLetIn;

  // Takes the page back after a "no"; answers whether it did.
  bool Function()? takeBack;

  // The caller's, which hears a guard's rejection there.
  OnNavigationFailure? onFailure;

  // The navigation waiting on the nested router of the page of [data], not
  // claimed yet.
  static _NestedLetIn? waitingOn(RouteData<Object?>? data) =>
      data == null ? null : _ofPage[data];

  // Takes the navigation waiting on the nested router of the page of [data],
  // for that router to let it in or turn it down.
  static _NestedLetIn? claim(RouteData<Object?> data) {
    final letIn = _ofPage[data];
    _ofPage[data] = null;
    return letIn;
  }

  // Waits on the nested router of the page of [data]. A page whose nested
  // router doesn't claim it by the end of the frame that builds the page,
  // such as one that holds tabs or no router, lets the navigation in then.
  void waitOn(RouteData<Object?> data) {
    _ofPage[data] = this;
    final binding = SchedulerBinding.instance;
    void letInUnclaimed(Duration _) {
      if (!identical(_ofPage[data], this)) return;
      _ofPage[data] = null;
      letIn();
    }

    // A page put on while widgets build is built in the next frame.
    switch (binding.schedulerPhase) {
      case .persistentCallbacks || .midFrameMicrotasks:
        binding.addPostFrameCallback(
          (_) => binding.addPostFrameCallback(letInUnclaimed),
        );
      case .idle || .transientCallbacks || .postFrameCallbacks:
        binding.addPostFrameCallback(letInUnclaimed);
    }
  }

  // Adds [step] to what is done once the navigation is let in.
  void addLetIn(VoidCallback step) {
    final before = _onLetIn;
    _onLetIn = before == null
        ? step
        : () {
            before();
            step();
          };
  }

  // The guards let the navigation in. A link a later link was let in after
  // gives way to it.
  void letIn() {
    final step = linkStep;
    final onLetIn = _onLetIn;
    linkStep = null;
    _onLetIn = null;
    takeBack = null;
    final link = this.link;
    if (link == null || !_root._isLinkOvertaken(link)) step?.call();
    onLetIn?.call();
  }

  // A guard turned the navigation down: nothing it waited for is done, and
  // the page is taken back, when [canTakeBack] and it can be. Answers
  // whether it was.
  bool turnDown({bool canTakeBack = true}) {
    final toTakeBack = canTakeBack ? takeBack : null;
    linkStep = null;
    _onLetIn = null;
    takeBack = null;
    return toTakeBack?.call() ?? false;
  }

  // The navigation goes on into the nested router of a page the nested
  // router this waited on put on: [inner] waits there in its place. A "no"
  // there takes back the page this would have taken back, the outermost one
  // the navigation put on.
  void handOnTo(_NestedLetIn inner) {
    inner
      ..link ??= link
      ..onFailure ??= onFailure
      ..takeBack = takeBack ?? inner.takeBack;
    final step = linkStep;
    if (step != null) {
      final innerStep = inner.linkStep;
      inner.linkStep = innerStep == null
          ? step
          : () {
              innerStep();
              step();
            };
    }
    final onLetIn = _onLetIn;
    if (onLetIn != null) inner.addLetIn(onLetIn);
    linkStep = null;
    _onLetIn = null;
    takeBack = null;
  }
}

// How a change of the active tab ended: the tab is active, its guards kept
// it out, or a later change replaced it while its guards decided.
enum _TabChange { done, rejected, replaced }

// What a batch does once every guard has let its routes through, as
// [accepted], right before their pages go on: returns the routes as they go
// on.
typedef _RoutesChange = List<RouteMatch<Object?>> Function(
  List<RouteMatch<Object?>> accepted,
);

// Called when a guard returns without an answer. [isWaitingOnUser] says it
// waits on the user, on screen: behind a redirect it started, or a page or a
// dialog it put on screen in its call. Answers whether the navigation let go
// of the guard's page, as a reevaluation does, see
// [StackRouter._letGoOfGuard].
typedef _GuardHoldsCallback = bool Function({required bool isWaitingOnUser});

// How many times in a row a guard is asked again because the state the
// guards are asked again for changed while it ran its check. A guard whose
// own check changes that state through code of the app, as one that
// refreshes a session the app listens to, would be asked without end.
const _kMaxAsksAgainInARow = 3;

// What replaceAll does to the pages it replaces, as its guards answer.
class _PagesReplacement {
  const new({
    required this.onGuardShowsPage,
    required this.onGuardReturned,
    required this.onGuardAnswered,
    required this.onPageGoesOn,
    required this.onPageWentOn,
    required this.onAllAccepted,
    required this.onRejected,
  });

  // A guard that has not answered puts a page of its own on the stack of the
  // given router, right after this returns.
  final ValueChanged<StackRouter> onGuardShowsPage;

  // A guard's call returned without an answer.
  final VoidCallback onGuardReturned;

  // The guards of a route have answered.
  final VoidCallback onGuardAnswered;

  // A new page goes on the stack these pages are on, right after this
  // returns, whoever puts it on.
  final VoidCallback onPageGoesOn;

  // The new page of the given data went on that stack.
  final ValueChanged<RouteData<Object?>> onPageWentOn;

  // Every guard let the routes through; see [_RoutesChange].
  final _RoutesChange onAllAccepted;

  // A guard rejected a route.
  final VoidCallback onRejected;

  // This replacement, with [then] called with the routes [onAllAccepted]
  // returns.
  _PagesReplacement thenOnAllAccepted(
    ValueChanged<List<RouteMatch<Object?>>> then,
  ) => .new(
    onGuardShowsPage: onGuardShowsPage,
    onGuardReturned: onGuardReturned,
    onGuardAnswered: onGuardAnswered,
    onPageGoesOn: onPageGoesOn,
    onPageWentOn: onPageWentOn,
    onRejected: onRejected,
    onAllAccepted: (accepted) {
      final replacing = onAllAccepted(accepted);
      then(replacing);
      return replacing;
    },
  );
}

class _RouterScopeResult<T extends RoutingController> {
  const new(this.router, this.matches);
  final T router;
  final List<RouteMatch<Object?>> matches;
}

/// Holds a one-time read initial routes value
/// used by declarative routing widgets
class PendingRoutesHandler {
  List<PageRouteInfo<Object?>>? _initialPendingRoutes;

  /// Whether [_initialPendingRoutes] is not empty
  bool get hasPendingRoutes => _initialPendingRoutes?.isNotEmpty == true;

  /// Reads [_initialPendingRoutes] without deleting it's value
  // peek is a public getter, so matching the field would mean a breaking rename.
  // ignore: match-getter-setter-field-names
  List<PageRouteInfo<Object?>>? get peek => _initialPendingRoutes;

  /// One time read pending routes
  ///
  /// [_initialPendingRoutes] is deleted after the read
  List<PageRouteInfo<Object?>>? get initialPendingRoutes {
    if (_initialPendingRoutes == null) return null;
    final routes = List.of(_initialPendingRoutes!);
    _initialPendingRoutes = null;
    return routes;
  }
}

/// Observers the current guards processing navigation event
class ActiveGuardObserver extends ValueNotifier<List<GuardEntry>> {
  /// Default controller
  new() : super([]);

  // A guard can finish after its router, and this observer, are disposed.
  bool _isDisposed = false;

  /// Adds `guard` to the list of active guards
  void _add(GuardEntry entry) {
    if (_isDisposed) return;
    value = [...value, entry];
  }

  /// Removes `guard` from the list of active guards
  void _remove(GuardEntry entry) {
    if (_isDisposed) return;
    value = [...value..remove(entry)];
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Whether there's a guard  pending completion
  ///
  /// A guard asked again by [StackRouter.reevaluateGuards] that returned
  /// without an answer doesn't count: it let go of its page, which left the
  /// screen, so nothing on screen waits for it.
  bool get guardInProgress => value.isNotEmpty;

  /// returns a list of active guards
  List<AutoRouteGuard> get activeGuards =>
      .unmodifiable(value.map((e) => e.guard));
}

/// A class that holds a guard and it's corresponding resolver
class GuardEntry {
  /// Default constructor
  const new(this.guard, this._resolver);

  /// The auto route guard
  final AutoRouteGuard guard;

  final NavigationResolver _resolver;
}

// Stands in for the route of a page the navigator has not built yet, so a
// [RoutePredicate] can still be asked about the page. It is a page route, as
// the page's own route will be, so [ModalRoute.withName] accepts it by the
// page's name. It is never handed to a navigator and builds nothing.
class _UnshownPageRoute extends PageRoute<Object?> {
  new(Page<Object?> page) : super(settings: page);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => .zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox.shrink();

  void release() => dispose();
}
