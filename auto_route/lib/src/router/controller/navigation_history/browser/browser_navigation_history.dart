import 'dart:async';

import 'package:auto_route/src/matcher/route_match.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_entry_list.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_writer.dart';
import 'package:auto_route/src/router/controller/navigation_history/navigation_history.dart';
import 'package:auto_route/src/router/controller/routing_controller.dart';
import 'package:auto_route/src/router/parser/default_route_parser.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show LocalKey, VoidCallback, protected;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart' show BuildContext;

/// The url state of every open page of [router] and the routers nested in
/// it that the system back reaches from the page on top, the first page
/// first: every page of a stack, and of tabs the active tab alone. A page
/// that holds a nested router stands for that router's pages.
///
/// Native behavior this holds to: Flutter's Navigator, where each back
/// closes the page on top of the innermost navigator that can pop, and then
/// the page that holds it.
List<UrlState> pagesUnderTop(RoutingController router) {
  final states = <UrlState>[];
  void collect(RoutingController controller, List<RouteMatch<Object?>> above) {
    final pages = controller is StackRouter
        ? controller.stackData
        : [?controller.currentChild];
    for (final data in pages) {
      final segments = [...above, data.route];
      final nested = controller.childControllers.lastWhereOrNull(
        (child) => child.matchId == data.matchId,
      );
      if (nested != null && nested.hasEntries) {
        collect(nested, segments);
      } else {
        states.add(
          UrlState.fromSegments([
            ...segments,
            ...?data.pendingChildren.lastOrNull?.flattened,
          ]),
        );
      }
    }
  }

  collect(router, const []);
  return states.isEmpty ? states : states.sublist(0, states.length - 1);
}

/// A [NavigationHistory] that keeps a browser's history as the pages of the
/// app are: one entry for each page on the way back, the browser on the
/// entry of the page on top.
///
/// It is the browser's one writer; the Router writes nothing. What the
/// entries should be is kept in a [HistoryEntryList], in the app's own time,
/// and a [HistoryWriter] brings the browser to it, so the browser ends the
/// same however fast the app navigates and whenever the browser lands.
///
/// When the browser moves by the user's hand, the app follows: the page of
/// the entry the browser landed on is shown again, which closes the pages
/// above it, or is opened anew from the routes the entry was written with.
///
/// Native behavior this holds to: Flutter's Navigator under Android's system
/// back and the iOS back gesture, where back closes the page on top and a
/// closed page never comes back; the browser's forward button and its
/// entries ahead follow the HTML History API.
class BrowserNavigationHistory extends NavigationHistory {
  /// Creates the history of [router] in [_browser].
  ///
  /// [landingLimit] is how long a step through the browser's history may
  /// take to land before the history reads where the browser stands.
  new(
    this.router,
    this._browser, {
    this.landingLimit = const Duration(seconds: 1),
  }) {
    // Nothing can be written before a Router shows the app.
    _writer.pause();
  }

  @override
  final StackRouter router;

  final HistoryBrowser _browser;

  /// How long a step through the browser's history may take to land.
  final Duration landingLimit;

  late final _list = HistoryEntryList(
    isPageOpen: (pageId) => controllerOfPage(pageId) != null,
    keepsOut: _browser.keepsOut,
  );

  // The user's moves need no listener here: the platform reports each one,
  // and the delegate then asks this history how to follow it.
  late final _writer = HistoryWriter(_browser, landingLimit: landingLimit);

  // The number of the app's top entry when the app last followed the browser.
  int? _topBeforeFollowing;

  int? _jumpTarget;
  int? _passedNumber;

  int get _followedNumber => _passedNumber ?? _browser.index;

  // The entry the browser landed on, while [routesOfBrowserEntry] takes the
  // pages above its page off their stack; see [onNewUrlState].
  UrlState? _landedEntry;

  UrlState? _followedEntry;

  // Whether the change being reported keeps the entries of closed pages
  // that are under the entry of an open one; see [rebuildUrlAfterPop].
  bool _keepsClosedUnder = false;
  bool _isDropScheduled = false;

  bool _isDisposed = false;

  @override
  bool get writesBrowser => true;

  /// Whether the browser holds what the app shows: nothing is left to
  /// write, and no step of this history's own is on its way.
  bool get isBrowserSettled => _writer.isIdle;

  /// Completes once the browser holds what the app shows.
  Future<void> whenBrowserSettled() => _writer.whenIdle();

  @override
  void rebuildUrlAfterPop({LocalKey? poppedPageId}) {
    // A page popped from under the page on top, as popUntil pops the pages in
    // between before the one on top, keeps its entry until the call is over:
    // the page on top is popped next, and the browser then steps back over
    // them all at once, which leaves each ahead for the forward button, as
    // pops from the top down do. One whose page on top stays, as a page
    // popped in a router that another page covers, loses its entry then.
    _keepsClosedUnder =
        poppedPageId != null && urlState.topMatch?.id != poppedPageId;
    try {
      rebuildUrl();
    } finally {
      _keepsClosedUnder = false;
    }
    if (_isDropScheduled || _isDisposed) return;
    _isDropScheduled = true;
    scheduleMicrotask(() {
      _isDropScheduled = false;
      if (!_isDisposed &&
          _list.didDropClosed(wayBack: [...pagesUnderTop(router), urlState])) {
        _writer.bringTo(_list.entries);
      }
    });
  }

  @override
  void Function({bool dropsChanges}) holdBrowserWrites() {
    final entriesBefore = _list.entries;
    _writer.hold();
    var isReleased = false;
    return ({bool dropsChanges = false}) {
      if (isReleased) return;
      isReleased = true;
      if (dropsChanges && !_isDisposed) _list.restore(entriesBefore);
      _writer.release(dropsChanges: dropsChanges);
    };
  }

  VoidCallback? _onJumpLeft;

  bool get _isOnJump =>
      _topNumber == _followedNumber && _writer.holdsAll(_list.entries);

  @override
  void Function({bool dropsChanges}) holdBrowserWritesForJump({
    required VoidCallback onLeft,
  }) {
    final release = holdBrowserWrites();
    _onJumpLeft = onLeft;
    return ({bool dropsChanges = false}) {
      if (identical(_onJumpLeft, onLeft)) _onJumpLeft = null;
      release(dropsChanges: dropsChanges);
    };
  }

  void _leaveJump() {
    final onLeft = _onJumpLeft;
    _onJumpLeft = null;
    onLeft?.call();
  }

  @override
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    final landed = _landedEntry;
    if (landed != null && !HistoryEntryList.isEntryOf(landed, newState)) {
      // The browser holds its entries already: only the url state changes.
      super.onNewUrlState(newState, notify: notify);
      return;
    }
    final takesFollowed = _takesFollowedEntry(newState);
    final state = takesFollowed
        ? newState.copyWith(shouldReplace: true)
        : newState;
    // A page that replaces one whose entry is owed is owed that entry too.
    final top = _topNumber;
    final replacesOwed =
        state.shouldReplace && _writer.owes(top, _list.entries.lastOrNull);
    final shown = _list.show(
      state,
      keepsClosedUnder: _keepsClosedUnder,
      under: pagesUnderTop(router),
      isLink: router.root.isShowingLink,
    );
    super.onNewUrlState(
      shown.copyWith(shouldReplace: state.shouldReplace),
      notify: notify,
    );
    final owed = takesFollowed
        ? _passedNumber
        : (replacesOwed && _topNumber == top ? top : null);
    if (owed != null) _writer.owe(owed, shown);
    _writer.bringTo(_list.entries, isReplace: state.shouldReplace);
    if (_onJumpLeft != null &&
        landed == null &&
        !takesFollowed &&
        !router.root.isShowingLink &&
        !_isOnJump) {
      _leaveJump();
    }
  }

  // Whether [state], as a guard's sign-in page, first takes [_followedEntry].
  bool _takesFollowedEntry(UrlState state) {
    final followed = _followedEntry;
    final top = _list.entries.lastOrNull;
    return followed != null &&
        top != null &&
        router.root.isFollowingBrowserEntry &&
        HistoryEntryList.isEntryOf(top, followed) &&
        !HistoryEntryList.isEntryOf(followed, state);
  }

  /// Starts this history over on the entry the browser stands on, which then
  /// holds the page on top: another history wrote the browser since, as when
  /// an app swaps its router and a Router shows this one again.
  @protected
  void takeBrowser() {
    _writer.restart();
    _writer.bringTo(_list.entries);
  }

  /// Stops writing the browser until [takeBrowser]: a Router shows another
  /// router now, whose history writes it.
  @protected
  void leaveBrowser() => _writer.restart();

  @override
  void markShownByRouter([BuildContext? routerContext]) {
    super.markShownByRouter(routerContext);
    if (_browser.canWrite) {
      _writer.resume();
      return;
    }
    // The Router builds its navigator in the frame that is on its way.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && _browser.canWrite) _writer.resume();
    });
  }

  @override
  bool consumeOwnBrowserMove(UrlState configuration) =>
      _writer.hasNothingToFollow(configuration);

  @override
  bool get isBrowserBehindApp {
    final at = _browser.index;
    if (at >= _topNumber) return false;
    // The top page's entry, as under a pushPathState one, asks no PopScope.
    final held = _writer.entryAt(at);
    final pageId = urlState.topMatch?.id;
    return held == null ||
        pageId == null ||
        held.topMatch?.id != pageId ||
        !isSameHistoryUrl(held.url, urlState.url);
  }

  @override
  void returnBrowserToApp() => _writer.bringTo(_list.entries);

  @override
  bool get isOnEntryBeforeApp => _isOnEntryBeforeApp;
  bool _isOnEntryBeforeApp = false;

  @override
  void followBrowser() {
    final at = _browser.index;
    final passed = [
      for (var number = _topNumber + 1; number < at; number++)
        _writer.entryAt(number),
    ];
    // Not the entry the engine pushes for a link, one after the browser's.
    final isTraversal =
        _writer.userStep > 1 || (_writer.entryAt(at)?.hasSegments ?? false);
    _passedNumber = null;
    _jumpTarget =
        _writer.isUserLanding &&
            isTraversal &&
            passed.isNotEmpty &&
            passed.every((entry) => entry?.hasSegments ?? false)
        ? at
        : null;
    if (_jumpTarget == null) _followTo(at);
  }

  @override
  UrlState? followPassedEntry() {
    final target = _jumpTarget;
    if (target == null) return null;
    final passed = _passedNumber;
    final top = _topNumber;
    // A passed entry whose page took no entry of its own ends the walk.
    final next = passed == null || passed == top ? top + 1 : target;
    if (next < target) {
      _passedNumber = next;
      _followTo(next);
      return _writer.entryAt(next);
    }
    _jumpTarget = null;
    _passedNumber = null;
    _followTo(target);
    return null;
  }

  void _followTo(int at) {
    final top = _topNumber;
    _topBeforeFollowing = top;
    _isOnEntryBeforeApp = false;
    _followedEntry = null;
    if (at == top) return;
    if (at < _writer.first) {
      // An entry from before the app started, as a reload leaves them under
      // the entry the app starts on: the app's entries start from it now.
      // The pages open now have their entries ahead of it, and its page
      // takes their place.
      _isOnEntryBeforeApp = true;
      _writer.first = at;
      _list.reset(
        [_browserEntry(at)],
        withEntriesAhead: [
          for (final page in [...pagesUnderTop(router), urlState])
            ?page.topMatch?.id,
        ],
      );
      return;
    }
    // The entries up to [at]. A page kept out of the address bar has none:
    // it closes with the pages over that entry.
    var number = _writer.first - 1;
    final followed = <UrlState>[];
    for (final (place, entry) in _list.entries.indexed) {
      final hasEntry = _writer.hasBrowserEntry(place, entry);
      if (hasEntry ? ++number > at : number >= at) break;
      followed.add(entry);
    }
    final ahead = _list.entries.skip(followed.length).toList();
    // And the browser's own: the entries ahead, or one made for a typed url.
    for (number++; number <= at; number++) {
      followed.add(_browserEntry(number));
    }
    // An open page whose own entries are all ahead, as the tab on screen after
    // back into another tab, gets no entry under a page shown here later.
    _list.reset(
      followed,
      withEntriesAhead: {
        for (final entry in ahead)
          if (entry.topMatch?.id case final pageId?
              when controllerOfPage(pageId) != null &&
                  !followed.any((kept) => kept.topMatch?.id == pageId))
            pageId,
      },
    );
  }

  // What the browser entry [number] holds: what this history wrote there,
  // or for an entry it never wrote, the url the browser shows when it stands
  // on it.
  UrlState _browserEntry(int number) {
    final isCurrent = number == _browser.index;
    return _writer.entryAt(number) ??
        UrlState(
          Uri.parse(isCurrent ? _browser.url : '/'),
          const [],
          pathState: isCurrent ? _browser.state : null,
        );
  }

  @override
  List<RouteMatch<Object?>>? routesOfBrowserEntry(UrlState configuration) {
    final held = _writer.entryAt(_followedNumber);
    if (held == null ||
        !held.hasSegments ||
        !isSameHistoryUrl(held.url, configuration.url)) {
      return null;
    }
    // The page to show: the entry's own, or one the app keeps out of the
    // address bar, which stands over it.
    final entry = _list.entries.lastOrNull ?? held;
    final pageId = entry.topMatch?.id;
    // The entry's page may still be under the current one with the same route
    // name, as when the same route was pushed twice, with the same params or
    // others; navigating to it alone would update the current page in place.
    if (pageId != null) {
      // The url the removal reports makes no entry, see [onNewUrlState].
      _landedEntry = entry;
      try {
        removePagesAbove(pageId);
      } finally {
        _landedEntry = null;
      }
      // The same page can show another url, as when its query params changed
      // in place; then the entry still needs to be shown.
      if (router.topMatch.id == pageId &&
          isSameHistoryUrl(urlState.url, entry.url)) {
        final isOwn = identical(entry, held) || !_browser.keepsOut(entry);
        if (isOwn && !isSameHistoryUrl(held.url, entry.url)) {
          // The browser stands on the number of the page's entry, but the
          // entry still holds another page's url: a step landed there
          // before the page's url was written, as the user's forward press
          // with this history's own step back, or the app's forward()
          // before a push. The page stays, and its url is written there.
          returnBrowserToApp();
        } else if (isOwn) {
          _takeOverEntryState(configuration.pathState);
        }
        return const [];
      }
    }
    _followedEntry = entry;
    return [UrlState.toHierarchy(entry.segments)];
  }

  @override
  (StackRouter, RouteMatch<Object?>)? pageToPushForBrowserEntry(
    UrlState configuration,
  ) {
    final at = _followedNumber;
    final entry = _writer.entryAt(at);
    final page = entry?.topMatch;
    final currentPageId = urlState.topMatch?.id;
    if (entry == null ||
        page == null ||
        currentPageId == null ||
        at - 1 != _topBeforeFollowing) {
      return null;
    }
    if (!isSameHistoryUrl(entry.url, configuration.url) ||
        !isSameHistoryUrl(urlState.url, entry.url)) {
      return null;
    }
    if (page.id == currentPageId || controllerOfPage(page.id) != null) {
      return null;
    }
    final holder = controllerOfPage(currentPageId);
    return holder is StackRouter ? (holder, page) : null;
  }

  /// Steps the browser back one entry, unless the app's first entry is
  /// current, behind what is still to be written.
  ///
  /// The tab may hold pages from before the app, such as the site the user
  /// came from; stepping back from the app's first entry would leave the app.
  @override
  void back() {
    if (!canNavigateBack) return;
    _leaveJump();
    _writer.step(-1);
  }

  @override
  void forward() {
    _leaveJump();
    _writer.step(1);
  }

  @override
  bool get canNavigateBack => _browser.index > 0;

  /// The number of the app's browser entries up to and including the current
  /// one.
  ///
  /// Counts by the engine's serial count, which starts at the app's first
  /// entry, so pages from before the app and entries ahead of the current one
  /// are left out.
  @override
  int get length => _browser.index + 1;

  @override
  void pushPathState(Object? state) {
    // Like history.pushState, always a new entry, also right after a replace,
    // and null is a state like any other; copyWith would keep the last
    // navigation's replace mark and can't set null.
    final newState = UrlState(
      urlState.uri,
      urlState.segments,
      pathState: state,
    );
    if (newState == urlState) return;
    _list.add(newState);
    super.onNewUrlState(newState);
    _writer.bringTo(_list.entries);
    _leaveJump();
  }

  @override
  Object? get pathState => urlState.pathState;

  @override
  void dispose() {
    _isDisposed = true;
    _writer.dispose();
    super.dispose();
  }

  // The number of the browser entry of the app's page on top: the entries
  // the app keeps out of the address bar have none.
  int get _topNumber {
    final written = _list.entries.indexed.where(
      (placed) => _writer.hasBrowserEntry(placed.$1, placed.$2),
    );
    return _writer.first + (written.isEmpty ? 0 : written.length - 1);
  }

  // The browser moved to an entry whose page the app already shows, as its
  // back button does from an entry made by [pushPathState]: the app takes
  // over the entry's state, [entryState], null included.
  void _takeOverEntryState(Object? entryState) {
    final shown = UrlState(
      urlState.uri,
      urlState.segments,
      pathState: entryState,
    );
    super.onNewUrlState(shown, notify: false);
    final entries = _list.entries;
    _list.reset([...entries.take(entries.length - 1), shown]);
    _writer.adopt(_followedNumber, shown);
  }
}
