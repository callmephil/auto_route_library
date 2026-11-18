import 'package:auto_route/src/matcher/route_match.dart';
import 'package:auto_route/src/router/controller/navigation_history/stub/navigation_history_impl.dart'
    if (dart.library.io) 'native/navigation_history_impl.dart'
    if (dart.library.js_interop) 'web/navigation_history_impl.dart';
import 'package:auto_route/src/router/controller/routing_controller.dart';
import 'package:auto_route/src/router/parser/default_route_parser.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// An abstraction on a navigation history tracker
/// that utilises browser history on web and mimics it on native
abstract class NavigationHistory with ChangeNotifier {
  /// Creates an instance of [NavigationHistoryImpl]
  static NavigationHistory create(StackRouter router) {
    return NavigationHistoryImpl(router);
  }

  /// Forces url to rebuild if generated state
  /// is different from current
  ///
  /// An empty stack has no url to record, so a replace mark is kept for the
  /// url that follows, such as the guarded page that takes the place of a
  /// [NavigationResolver.redirectUntil] page.
  void rebuildUrl() {
    final newState = UrlState.fromSegments(
      router.currentSegments,
      shouldReplace: _isUrlStateMarkedForReplace,
    );
    if (newState.hasSegments) {
      _unMarkUrlStateForReplace();
    }
    onNewUrlState(newState);
  }

  /// Rebuilds the url after a page was popped from one of [router]'s stacks.
  ///
  /// A pop leaves the page that was under the popped one on top. Recording
  /// that page as a new entry, as [rebuildUrl] would, leaves the popped page's
  /// entry in the history, so a later [back] returns to the page that was just
  /// popped. The native history instead drops the popped page's entry and
  /// keeps one entry for the page now on top. The web history cannot delete
  /// browser entries: when an entry before holds the page now on top, and the
  /// entries between hold only pages that are closed, as after
  /// [StackRouter.popUntil], it steps the browser back to it (see
  /// [consumeOwnBrowserMove]); otherwise it gives the popped page's entry to
  /// the page now on top.
  ///
  /// [poppedPageId] is the id of the popped page's route. A page can be popped
  /// from under the page on top, as [StackRouter.popUntil] pops the pages in
  /// between; the url then stays the same, and the native history drops the
  /// popped page's entries by this id.
  ///
  /// Like [rebuildUrl], notifies listeners only if the url changed, which it
  /// does not when the popped page was not part of the visible url.
  @internal
  void rebuildUrlAfterPop({LocalKey? poppedPageId}) => rebuildUrl();

  /// Rebuilds the url after pages were closed before a navigator built them,
  /// as a pop right after a push closes the pushed page.
  ///
  /// [closedPageIds] are the ids of those pages' routes. Such a page got its
  /// entry as it was pushed, and no navigator reports its pop. The native
  /// history drops the entries that showed it, as [rebuildUrlAfterPop] drops
  /// a popped page's, or a later [back] would open the closed page again. The
  /// web history rebuilds the url as after any other change.
  @internal
  void rebuildUrlAfterClosingUnbuilt(Iterable<LocalKey> closedPageIds) =>
      rebuildUrl();

  /// Whether [configuration], a route the Router just handed over, only
  /// confirms a move through the browser history that this history made
  /// itself, or is a url the Router parsed again from its provider while
  /// this history still had entries to write.
  ///
  /// The web history sometimes moves the browser on its own, for example to
  /// step back over a page that was popped in the app. The browser then reports
  /// the entry it lands on like any navigation by the user, although the app
  /// already shows that route. [AutoRouterDelegate.setNewRoutePath] skips such
  /// a report instead of handling it as a deep link, which would close dialogs,
  /// rerun the deep link builder and rebuild the stack.
  ///
  /// Only the first report after the move can match, and a report for a
  /// different url returns false and is handled as usual. Always false on
  /// native platforms, where the history never moves on its own.
  @internal
  bool consumeOwnBrowserMove(UrlState configuration) => false;

  /// The routes the app showed when it wrote the browser entry that
  /// [configuration], a route the platform just reported, came from.
  ///
  /// A browser entry holds only a url, so a page reopened from it by the
  /// browser's back or forward button would lose the arguments the url can't
  /// carry. The web history remembers the routes of each entry it wrote, with
  /// their arguments, and [AutoRouterDelegate.setNewRoutePath] navigates to
  /// those instead of the routes parsed from the url.
  ///
  /// Returns a single route holding its children, as [UrlState.toHierarchy]
  /// builds it, or null when the current entry wasn't written by this history
  /// or now holds a different url, such as one typed into the address bar.
  /// Returns an empty list when the entry's page is still open and is now
  /// the top page: there is nothing to navigate to, and navigating to it
  /// again would run its guards again. The app then takes over the entry's
  /// [pathState], as when the browser's back button leaves an entry made by
  /// [pushPathState]. Always null on native platforms.
  @internal
  List<RouteMatch<Object?>>? routesOfBrowserEntry(UrlState configuration) =>
      null;

  /// The page to push, and the stack to push it on, to follow the browser to
  /// the entry that [configuration], a route the platform just reported, came
  /// from, when that entry is the next one after the app's and holds a page
  /// that was pushed over the app's current page with the same url.
  ///
  /// The browser's forward button reopens such an entry after going back
  /// between two pages with the same url. Navigating to its routes would
  /// update the current page in place instead, since it has the same route
  /// name, so [AutoRouterDelegate.setNewRoutePath] pushes this page instead.
  /// Null otherwise, and always on native platforms.
  @internal
  (StackRouter, RouteMatch<Object?>)? pageToPushForBrowserEntry(
    UrlState configuration,
  ) => null;

  /// Whether the browser now shows an entry before the one holding the app's
  /// url, as after its back button, while the app hasn't followed yet.
  ///
  /// [AutoRouterDelegate.setNewRoutePath] asks this before following a route
  /// the browser reported, so that a page that refuses to be popped, through
  /// a PopScope, can refuse the browser's back button too.
  /// False when that entry holds the page the app shows, as the one before an
  /// entry made by [pushPathState]: going back to it closes no page, so there
  /// is nothing to refuse. Always false on native platforms, which have no
  /// browser.
  @internal
  bool get isBrowserBehindApp => false;

  /// Moves the browser forward again to the entry holding the app's url,
  /// after the app refused to follow a back step the browser made.
  ///
  /// The browser reports that entry when it gets there, and
  /// [consumeOwnBrowserMove] matches that report. Does nothing on native
  /// platforms, or when [isBrowserBehindApp] is false.
  @internal
  // ignore: no-empty-block
  void returnBrowserToApp() {
    // Native platforms have no browser to move.
  }

  /// Holds back what this history writes to the browser until the returned
  /// function is called, and then writes only where the app's entries ended.
  /// Called with `dropsChanges`, it writes nothing of what was held, and the
  /// entries are as they were: the app took the change back.
  ///
  /// For a change the app may take back in the frame that follows: a browser
  /// entry, once written, can only be stepped back over, so a change taken
  /// back leaves one behind unless it was never written. Does nothing on
  /// native platforms.
  @internal
  void Function({bool dropsChanges}) holdBrowserWrites() => _doNothing;

  // Native platforms have no browser to write.
  // ignore: no-empty-block
  static void _doNothing({bool dropsChanges = false}) {}

  /// Makes this history's account of the app's entries start from the entry
  /// the browser now stands on, before [AutoRouterDelegate.setNewRoutePath]
  /// follows the browser there: the entries after it are the browser's, as
  /// the ones its forward button goes to. Does nothing when the browser
  /// stands on the entry of the app's page on top, as when the platform
  /// hands over a link, and on native platforms.
  @internal
  // ignore: no-empty-block
  void followBrowser() {
    // Native platforms have no browser to follow.
  }

  /// Whether [followBrowser] last followed the browser onto an entry from
  /// before the app started, as its back button reaches after a reload.
  ///
  /// The app knows such an entry only by its url and the state saved in it,
  /// so [AutoRouterDelegate.setNewRoutePath] opens it as a link to its url
  /// whose pages take the place of the app's: those have their entries
  /// ahead of it, where the forward button reaches them again. Always false
  /// on native platforms.
  @internal
  bool get isOnEntryBeforeApp => false;

  /// Whether this history writes the app's urls to a browser itself, entry
  /// by entry, so that the Router must write none: its
  /// [AutoRouterDelegate.currentConfiguration] is then null. False on native
  /// platforms, where the Router reports the url to the platform.
  @internal
  bool get writesBrowser => false;

  /// Pushes a new browser entry with given state
  ///
  /// Like history.pushState, it adds an entry also right after a navigation
  /// that replaced the current one, and takes null to push an entry without
  /// a state. Pushes nothing when [state] equals the current [pathState].
  ///
  /// only works for web
  void pushPathState(Object? state);

  /// Reads the current browser entry state
  ///
  /// only works for web
  Object? get pathState;

  /// Whether a Router shows this history's router, which it does once it
  /// has built the router's [AutoRouterDelegate]: the urls can then be
  /// written to the platform.
  ///
  /// Until then the app may navigate, as before runApp, with no Router and no
  /// binding yet; the web history keeps what it has to write until then.
  @internal
  bool get isShownByRouter => _isShownByRouter;
  bool _isShownByRouter = false;

  /// Marks that a Router shows this history's router; see
  /// [isShownByRouter]. [routerContext] is the context that Router builds
  /// the router's [AutoRouterDelegate] with, which finds the Router also
  /// while the app shows no page.
  @internal
  void markShownByRouter([BuildContext? routerContext]) =>
      _isShownByRouter = true;

  bool _isUrlStateMarkedForReplace = false;

  /// Whether next browser entry update should replace current
  bool get isUrlStateMarkedForReplace => _isUrlStateMarkedForReplace;

  /// Force next browser entry update to replace current
  void markUrlStateForReplace() => _isUrlStateMarkedForReplace = true;

  void _unMarkUrlStateForReplace() => _isUrlStateMarkedForReplace = false;

  UrlState _urlState = UrlState.fromSegments(const []);

  /// Notifies `AutoRouteDelegate` of url configuration changed
  /// if [newState] is different from current
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    // Two pages of the same route with equal arguments have equal url states.
    // Only the page on top tells them apart.
    if (_urlState != newState ||
        _urlState.topMatch?.id != newState.topMatch?.id) {
      _urlState = newState;
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// Whether this route is in the visible urlState-segments
  bool isRouteActive(String routeName) {
    return urlState.segments.any((r) => r.name == routeName);
  }

  /// Whether this route-data is in the visible urlState-segments
  ///
  /// Compares the page too, since the same route can be pushed twice with
  /// equal arguments.
  bool isRouteDataActive(RouteData<Object?> data) {
    return urlState.segments.any(
      (route) => route == data.route && route.id == data.route.id,
    );
  }

  /// Whether this path-pattern is in the visible urlState-segments
  bool isPathActive(String pattern) {
    return RegExp(pattern).hasMatch(urlState.path);
  }

  /// The controller, [router] or one nested in it, whose stack holds the page
  /// with [pageId], or null when no stack holds it any more.
  @protected
  RoutingController? controllerOfPage(
    LocalKey pageId, [
    RoutingController? controller,
  ]) {
    controller ??= router;
    if (controller.stackData.any((data) => data.route.id == pageId)) {
      return controller;
    }
    for (final child in controller.childControllers) {
      final holder = controllerOfPage(pageId, child);
      if (holder != null) return holder;
    }
    return null;
  }

  /// Removes the pages above the page with [pageId] from the stack that holds
  /// it.
  ///
  /// Going back to a page that is still under the current one with the same
  /// route name, as when the same route was pushed twice, needs this first:
  /// navigating to it alone would update the current page in place.
  ///
  /// The pages of a router built by `AutoRouter.declarative` stay: the app's
  /// list decides them, and the navigation reaches the app as its
  /// `onNavigate`.
  @protected
  void removePagesAbove(LocalKey pageId) {
    final holder = controllerOfPage(pageId);
    if (holder is StackRouter && !holder.managedByWidget) {
      holder.removeUntil((data) => data.route.id == pageId);
    }
  }

  /// Helper to access current [_urlState]
  UrlState get urlState => _urlState;

  /// The root router
  StackRouter get router;

  /// Whether managed history has more than one entry
  bool get canNavigateBack;

  /// The length of managed history entries
  int get length;

  /// Navigate back one entry in history
  ///
  /// does nothing if history has only one entry
  void back();

  /// Navigate forward one entry in history
  ///
  /// only works for web
  void forward();
}
