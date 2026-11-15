// The methods in this file are optional hooks. The router calls them on every
// observer and subscriber, so an empty body is how a hook ignores its event.
// Throwing or making them abstract would break apps that skip one.
// ignore_for_file: no-empty-block

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

/// An extended version of  [NavigatorObserver] to support
/// Tab-int and tab-change events observation
class AutoRouterObserver extends NavigatorObserver {
  /// called when a tab route activates
  // A hook for subclasses: the default does nothing with what it is told.
  void didInitTabRoute(TabPageRoute _, TabPageRoute? _) {
    // Does nothing: a hook for subclasses.
  }

  /// called when tab route reactivates
  // A hook for subclasses: the default does nothing with what it is told.
  void didChangeTabRoute(TabPageRoute _, TabPageRoute _) {
    // Does nothing: a hook for subclasses.
  }
}

/// An interface used to mark classes as AutoRouteAware entities
/// usually implemented by widget States
mixin class AutoRouteAware {
  /// Creates an entity that listens to route changes.
  const new();

  /// Called when the top route has been popped off, and the current route
  /// shows up.
  void didPopNext() {
    // Does nothing: a hook for implementers.
  }

  /// Called when the current route has been pushed.
  void didPush() {
    // Does nothing: a hook for implementers.
  }

  /// Called when the current route has been popped off.
  void didPop() {
    // Does nothing: a hook for implementers.
  }

  /// Called when a new route has been pushed, and the current route is no
  /// longer visible.
  void didPushNext() {
    // Does nothing: a hook for implementers.
  }

  /// called when a tab route activates
  // A hook for implementers: the default does nothing with what it is told.
  void didInitTabRoute(TabPageRoute? _) {
    // Does nothing: a hook for implementers.
  }

  /// called when tab route reactivates
  // A hook for implementers: the default does nothing with what it is told.
  void didChangeTabRoute(TabPageRoute _) {
    // Does nothing: a hook for implementers.
  }
}

/// a helper mixin to utilises [AutoRouteAware] in a better manner
/// and reduce boilerplate code
mixin AutoRouteAwareStateMixin<T extends StatefulWidget> on State<T>
    implements AutoRouteAware {
  AutoRouteObserver? _observer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RouterScope exposes the list of provided observers
    // including inherited observers
    _observer = RouterScope.of(context)
        .firstObserverOfType<AutoRouteObserver>();
    // A widget shown outside a page, as in a dialog, has no route data to
    // subscribe to, so it hears nothing rather than throwing.
    final routeData = context
        .findAncestorWidgetOfExactType<RouteDataScope>()
        ?.routeData;

    if (routeData != null) {
      // we subscribe to the observer by passing our
      // AutoRouteAware state and the scoped routeData
      _observer?.subscribe(this, routeData);
    }
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeTabRoute(TabPageRoute _) {
    // Does nothing: a hook for the state that uses this mixin.
  }

  @override
  void didInitTabRoute(TabPageRoute? _) {
    // Does nothing: a hook for the state that uses this mixin.
  }

  @override
  void didPop() {
    // Does nothing: a hook for the state that uses this mixin.
  }

  @override
  void didPush() {
    // Does nothing: a hook for the state that uses this mixin.
  }

  @override
  void didPopNext() {
    // Does nothing: a hook for the state that uses this mixin.
  }

  @override
  void didPushNext() {
    // Does nothing: a hook for the state that uses this mixin.
  }
}

/// A [Navigator] observer that notifies [AutoRouteAware]s of changes to the
/// state of their [Route].
///
/// [AutoRouteObserver] informs subscribers whenever a route of type `R` is
/// pushed on top of their own route of type `R` or popped from it. This is for
/// example useful to keep track of page transitions, e.g. a
/// `RouteObserver<PageRoute>` will inform subscribed [AutoRouteAware]s whenever
/// the user navigates away from the current page route to another page route.
///
/// A subclass that overrides [didPush], [didPop], [didRemove], [didReplace],
/// [didInitTabRoute] or [didChangeTabRoute] must call `super` in it. These
/// methods tell the subscribers what happened to their routes, and the first
/// four also forget each route that leaves the [Navigator]. Without `super`,
/// the subscribers of the routes involved hear nothing, and a route that
/// left keeps its subscribers until they unsubscribe.
class AutoRouteObserver extends AutoRouterObserver {
  // Subscribers of the pages in this observer's navigator, keyed by the route
  // that shows each page, as Flutter's RouteObserver keys them. Two pages of
  // one route, such as /item/1 under /item/2, share the route's key, but each
  // has a route of its own.
  final Map<Route<Object?>, Set<AutoRouteAware>> _routeListeners = {};

  // Subscribers of tab pages, which have no navigator route, keyed by the
  // route's key. A tabs router shows each of its routes once.
  final Map<LocalKey, Set<AutoRouteAware>> _listeners =
      <LocalKey, Set<AutoRouteAware>>{};

  // Subscribers of routes inside nested routers, keyed by the route in this
  // observer's navigator that hosts them, each with the route it subscribed to.
  final Map<Route<Object?>, Map<AutoRouteAware, RouteData<Object?>>>
  _nestedListeners = {};

  // The observers of ancestor navigators each subscriber was added to.
  final Map<AutoRouteAware, Set<AutoRouteObserver>> _ancestorObservers = {};

  // The route each stack page's subscriber was filed under. A page that is
  // closing can subscribe again, as when its State depends on something that
  // changes on the pop, after its route is forgotten; the subscriber is known
  // here, so it isn't taken for a new page.
  final Map<AutoRouteAware, Route<Object?>> _routeOfSubscriber = {};

  // The key each tab page's subscriber was filed under.
  final Map<AutoRouteAware, LocalKey> _tabKeyOfSubscriber = {};

  // The tab each tab's init came from, as observers heard it, kept to the
  // end of the frame. A page its init opens subscribes as it is built, after
  // the report, and hears the same tab. The tabs router's previousIndex can't
  // name it when a change of the tabs list opened the page: the tab that left
  // has no index in the new list.
  final Map<LocalKey, TabPageRoute?> _previousOfInit = {};
  var _isForgettingInits = false;

  /// Subscribe [AutoRouteAware] to be informed about changes to [route].
  ///
  /// Going forward, [AutoRouteAware] will be informed about qualifying changes
  /// to [route], e.g. when [route] is covered by another route or when [route]
  /// is popped off the [Navigator] stack. Each page is told only its own
  /// changes, also when two pages of one route are in the stack.
  ///
  /// When [route] is inside a nested router, [AutoRouteAware] is also informed
  /// while [route] shows inside its host route, when the host route is covered,
  /// uncovered or popped in an ancestor navigator that has an
  /// [AutoRouteObserver].
  ///
  /// Subscribing [AutoRouteAware] again while it is subscribed does nothing.
  void subscribe(AutoRouteAware routeAware, RouteData<Object?> route) {
    if (_routeOfSubscriber.containsKey(routeAware) ||
        _tabKeyOfSubscriber.containsKey(routeAware)) {
      return;
    }
    switch (_routeOf(route)) {
      case final shown?:
        _routeListeners.putIfAbsent(shown, () => {}).add(routeAware);
        _routeOfSubscriber[routeAware] = shown;
      case null:
        _listeners.putIfAbsent(route.key, () => {}).add(routeAware);
        _tabKeyOfSubscriber[routeAware] = route.key;
    }
    _subscribeToAncestors(routeAware, route);
    final router = route.router;
    if (router is TabsRouter && _previousOfInit.containsKey(route.key)) {
      routeAware.didInitTabRoute(_previousOfInit[route.key]);
    } else if (router is TabsRouter) {
      final previousIndex = router.previousIndex;
      final previous = previousIndex == null || previousIndex < 0
          ? null
          : router.stackData.elementAtOrNull(previousIndex);
      if (previousIndex != null && previous != null) {
        final previousRoute = TabPageRoute(
          routeInfo: previous.route,
          index: previousIndex,
        );
        routeAware.didInitTabRoute(previousRoute);
      } else {
        routeAware.didInitTabRoute(null);
      }
    } else {
      routeAware.didPush();
    }
    // A page built while covered, as under a deep link's top page, missed
    // the push that covered it: the navigator reported it before this page
    // existed to subscribe. A tab page is covered when its tabs are.
    if (_isCovered(routeAware, route)) routeAware.didPushNext();
  }

  // The route the navigator of [data]'s router shows its page with, or null
  // for a page no navigator shows, such as a tab page. The router's own
  // observer tracks the routes, so this doesn't depend on a subclass of this
  // observer calling super, and forgets those of a navigator that was disposed.
  static Route<Object?>? _routeOf(RouteData<Object?> data) {
    final router = data.router;
    if (router is! StackRouter) return null;
    return router.pagelessRoutesObserver.routeWhere(
      (route) => switch (route.settings) {
        final AutoRoutePage<Object?> page =>
          page.routeData.matchId == data.matchId,
        _ => false,
      },
    );
  }

  // Whether another page covers [route] in its own router, or covers a host
  // route of it in an ancestor router whose observer tells [routeAware] when
  // that host shows again, as it does while [route] shows in that host.
  bool _isCovered(AutoRouteAware routeAware, RouteData<Object?> route) {
    if (_isBelowTop(route)) return true;
    final ancestorObservers =
        _ancestorObservers[routeAware] ?? const <AutoRouteObserver>{};
    for (
      var host = route.parent;
      host != null && host.parent != null;
      host = host.parent
    ) {
      final hostData = host;
      if (!_isBelowTop(hostData) || !_isShownInHost(route, hostData.key)) {
        continue;
      }
      final hostRoute = _routeOf(hostData);
      if (hostRoute != null &&
          ancestorObservers.any(
            (observer) =>
                observer._nestedListeners[hostRoute]?.containsKey(routeAware) ??
                false,
          )) {
        return true;
      }
    }
    return false;
  }

  static bool _isBelowTop(RouteData<Object?> route) {
    final router = route.router;
    return router is StackRouter &&
        switch (router.stackData.lastOrNull) {
          final top? => top.matchId != route.matchId,
          null => false,
        };
  }

  /// Unsubscribe [AutoRouteAware].
  ///
  /// [AutoRouteAware] is no longer informed about changes to its route. If the
  /// given argument was subscribed to multiple types, this will unregister it
  /// (once) from each type.

  void unsubscribe(AutoRouteAware routeAware) {
    // A route or key left with no subscribers is dropped, so a navigator
    // that was disposed, which reports no removal, leaves nothing behind once
    // its pages are gone.
    if (_routeOfSubscriber.remove(routeAware) case final route?) {
      _removeSubscriber(_routeListeners, route, routeAware);
    }
    if (_tabKeyOfSubscriber.remove(routeAware) case final key?) {
      _removeSubscriber(_listeners, key, routeAware);
    }
    for (final observer
        in _ancestorObservers.remove(routeAware) ??
            const <AutoRouteObserver>{}) {
      for (final hostRoute in observer._nestedListeners.keys.toList()) {
        final nestedSubscribers = observer._nestedListeners[hostRoute];
        if (nestedSubscribers == null) continue;
        nestedSubscribers.remove(routeAware);
        if (nestedSubscribers.isEmpty) {
          observer._nestedListeners.remove(hostRoute);
        }
      }
    }
  }

  static void _removeSubscriber<K extends Object>(
    Map<K, Set<AutoRouteAware>> listeners,
    K key,
    AutoRouteAware routeAware,
  ) {
    final subscribers = listeners[key];
    if (subscribers == null) return;
    subscribers.remove(routeAware);
    if (subscribers.isEmpty) listeners.remove(key);
  }

  // Adds [routeAware] to the observers of the navigators that hold the host
  // routes of [route], so it hears when one of them is covered or uncovered.
  void _subscribeToAncestors(
    AutoRouteAware routeAware,
    RouteData<Object?> route,
  ) {
    // The root router's own route data has no parent and no navigator around
    // it.
    for (
      var host = route.parent;
      host != null && host.parent != null;
      host = host.parent
    ) {
      final router = host.router;
      final hostRoute = _routeOf(host);
      if (router is! StackRouter || hostRoute == null) continue;
      final observers =
          router.navigatorKey.currentState?.widget.observers ??
          const <NavigatorObserver>[];
      for (final observer in observers.whereType<AutoRouteObserver>()) {
        if (identical(observer, this)) continue;
        observer._nestedListeners.putIfAbsent(hostRoute, () => {})[routeAware] =
            route;
        _ancestorObservers.putIfAbsent(routeAware, () => {}).add(observer);
      }
    }
  }

  // Calls [notify] for each subscriber of a route that shows inside the route
  // with [hostKey], skipping those covered in their own router or in an
  // inactive tab.
  void _notifyNested(
    Route<Object?> hostRoute,
    void Function(AutoRouteAware routeAware) notify,
  ) {
    final nestedSubscribers = _nestedListeners[hostRoute];
    final hostPage = hostRoute.settings;
    if (nestedSubscribers == null || hostPage is! AutoRoutePage) return;
    final hostKey = hostPage.routeKey;
    for (final MapEntry(key: routeAware, value: route)
        in nestedSubscribers.entries.toList()) {
      if (_isShownInHost(route, hostKey)) notify(routeAware);
    }
  }

  static bool _isShownInHost(RouteData<Object?> route, LocalKey hostKey) {
    for (
      RouteData<Object?>? data = route;
      data != null && data.key != hostKey;
      data = data.parent
    ) {
      if (data.router.currentChild?.matchId != data.matchId) return false;
    }
    return true;
  }

  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {
    _previousOfInit[route.routeInfo.key] = previousRoute;
    if (!_isForgettingInits) {
      _isForgettingInits = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isForgettingInits = false;
        _previousOfInit.clear();
      });
    }
    final subscribers = _listeners[route.routeInfo.key]?.toList();
    if (subscribers != null) {
      for (final routeAware in subscribers) {
        routeAware.didInitTabRoute(previousRoute);
      }
    }
  }

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) {
    final subscribers = _listeners[route.routeInfo.key]?.toList();
    if (subscribers != null) {
      for (final routeAware in subscribers) {
        routeAware.didChangeTabRoute(previousRoute);
      }
    }
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    _notifyPop(route, previousRoute);
    _forget(route);
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    // navigate() and popUntil() remove a page instead of popping it when, for
    // example, a dialog above it is still closing. When that shows the route
    // underneath again, its subscribers hear what a pop would tell them.
    if (previousRoute != null && previousRoute.isCurrent) {
      _notifyPop(route, previousRoute);
    }
    _forget(route);
  }

  void _notifyPop(Route<Object?> route, Route<Object?>? previousRoute) {
    if (route.settings is! AutoRoutePage) return;
    // The page that leaves hears first, then the page that shows again, as
    // on a push, where the covered page hears didPushNext before the new
    // page subscribes and hears didPush. The page that leaves hears didPop
    // whatever shows under it, such as a page opened with pushWidget.
    for (final routeAware
        in _routeListeners[route]?.toList() ?? const <AutoRouteAware>[]) {
      routeAware.didPop();
    }
    _notifyNested(route, (routeAware) => routeAware.didPop());

    if (previousRoute == null || previousRoute.settings is! AutoRoutePage) {
      return;
    }
    for (final routeAware
        in _routeListeners[previousRoute]?.toList() ??
            const <AutoRouteAware>[]) {
      routeAware.didPopNext();
    }
    _notifyNested(previousRoute, (routeAware) => routeAware.didPopNext());
  }

  // Forgets [route] once its navigator no longer shows it.
  void _forget(Route<Object?> route) {
    _routeListeners.remove(route);
    _nestedListeners.remove(route);
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    if (route.settings is AutoRoutePage &&
        previousRoute != null &&
        previousRoute.settings is AutoRoutePage) {
      for (final routeAware
          in _routeListeners[previousRoute]?.toList() ??
              const <AutoRouteAware>[]) {
        routeAware.didPushNext();
      }
      _notifyNested(previousRoute, (routeAware) => routeAware.didPushNext());
    }
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    if (oldRoute != null) _forget(oldRoute);
  }
}

/// Holds information of Tab-init and Tab-changed events
/// used in [AutoRouteAware] and [AutoRouterObserver]
class TabPageRoute {
  /// default constructor
  const new({required this.routeInfo, required this.index});

  /// match information of the target tab
  final RouteMatch<Object?> routeInfo;

  /// index of the target tab
  final int index;

  /// helper getter to access [RouteMatch.name]
  String get name => routeInfo.name;

  /// helper getter to access [RouteMatch.path]
  String get path => routeInfo.path;

  /// helper getter to access [RouteMatch.stringMatch]
  String get match => routeInfo.stringMatch;
}

/// Adds auto-route data getter
/// to [Route]
extension RouteX<T> on Route<T> {
  /// Returns RouteData of this page if
  /// it's an [AutoRoutePage] otherwise it
  /// returns null
  RouteData<Object?>? get data {
    if (settings is AutoRoutePage) {
      return (settings as AutoRoutePage).routeData;
    }
    return null;
  }
}
