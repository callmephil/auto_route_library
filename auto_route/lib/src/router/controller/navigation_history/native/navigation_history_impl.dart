import 'dart:async';

import 'package:auto_route/auto_route.dart'
    show RouteMatch, RoutingController, StackRouter, UrlState;
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart'
    show pagesUnderTop;
import 'package:auto_route/src/router/controller/navigation_history/browser/history_entry_list.dart'
    show isSameHistoryUrl;
import 'package:auto_route/src/router/controller/navigation_history/navigation_history.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' hide mergeSort;
import 'package:flutter/scheduler.dart';

/// An implementation of [NavigationHistory]
/// That's used for native platforms
class NavigationHistoryImpl extends NavigationHistory {
  /// Creates the history of [router], the root router, and listens to it.
  new(this.router) {
    // The root router hears of every change to its stacks and to the stacks
    // nested in it, also of one that reports no url, such as the pages of a
    // link going in after the link reported its url.
    router.addListener(_onStacksChanged);
  }

  @override
  final StackRouter router;

  // The most entries the history keeps; the oldest go first.
  static const _maxEntries = 21;

  final _entries = <_HistoryEntry>[];
  bool _isNavigatingBack = false;
  // The url back() navigates to, until the router reports it.
  String? _backTargetUrl;
  int _backCount = 0;
  bool _isRebuildingAfterPop = false;

  // Whether the last entry left with its page at a change reported before
  // its url: the place on top is then free for the url that follows.
  bool _isTopFree = false;

  // The entries whose page a stack has held. Only such an entry leaves with
  // its page: the entry of a link whose page a guard has yet to let in holds
  // a page that is not open yet.
  final _wasOpen = Set<_HistoryEntry>.identity();

  // For each entry whose page no stack has held yet, as that of a navigation
  // a guard still decides, how many pages of the way to it stacks have
  // held at most. When fewer are held again, a page on that way left, as
  // the page a guard's no takes back, so the navigation can't land any more.
  final _heldDepths = Map<_HistoryEntry, int>.identity();

  // The pages that share the entry of a page over them, as the pages a link
  // opened under its page, each with the id of the page whose entry it
  // shares.
  final _sharing = <LocalKey, LocalKey>{};

  // The pages whose entry a link made.
  final _linkPages = <LocalKey>{};

  // The ids of the open pages that have been on the way back at a url report:
  // only a page new on it since gets an entry under the page on top. A page
  // stays here while it is open, also off the way back, as in a tab not
  // shown, so a page the limit dropped never gets its entry again.
  var _wayBackIds = <LocalKey>{};

  @override
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    super.onNewUrlState(newState, notify: notify);
    if (_isNavigatingBack && newState.url == _backTargetUrl) {
      // Ends after the current call, which may still report urls on its way.
      // A step back the router has taken as back() returns ends there.
      final backCount = _backCount;
      scheduleMicrotask(() {
        if (backCount == _backCount) _stopNavigatingBack();
      });
    }
    final didDropTop = _dropClosed() || _isTopFree;
    _isTopFree = false;
    _addTopEntry(newState, isTopFree: didDropTop);
    _giveLinkEntryToTop();
    _giveEntriesUnderTop(urlState);
    _wayBackIds = {
      ..._wayBackIds.where((pageId) => controllerOfPage(pageId) != null),
      for (final page in [...pagesUnderTop(router), urlState])
        ?page.topMatch?.id,
    };
  }

  // Brings the entries to the stacks after a change that may report no url:
  // an entry whose page has gone in counts as once open from then on, so it
  // leaves with its page, and the entry of a page that left goes at once, so
  // length and canNavigateBack count the pages open.
  void _onStacksChanged() {
    if (_dropClosed()) _isTopFree = true;
    _giveLinkEntryToTop();
    // Pages that go in with no url report, as those of a nested router built
    // a frame after the call that put its page on, get their entries now.
    _giveEntriesUnderTop(UrlState.fromSegments(router.currentSegments));
  }

  // Gives the last entry, made by a link for a page not open yet, to the
  // page on top once the link has landed on a page already open with the
  // same url: that page keeps its own id, so the link's never goes in. When
  // the entry before is that page's own, the two are one.
  void _giveLinkEntryToTop() {
    final last = _entries.lastOrNull;
    if (last == null || _wasOpen.contains(last) || _isOpen(last)) return;
    final top = UrlState.fromSegments(router.currentSegments);
    final topId = top.topMatch?.id;
    if (topId == null ||
        topId == last.pageId ||
        !isSameHistoryUrl(top.url, last.url) ||
        controllerOfPage(topId) == null) {
      return;
    }
    _entries.removeLast();
    if (_entries.lastOrNull?.pageId == topId) return;
    final entry = _entryOf(top);
    _entries.add(entry);
    _markIfHeld(entry);
  }

  // Adds the entry of the page on top of [newState], unless it has one.
  // [isTopFree] tells that the last entry just left with its page.
  void _addTopEntry(UrlState newState, {required bool isTopFree}) {
    // Don't add entries during back navigation to prevent duplicates, except
    // for a page that took the place of the page back() goes to, at its url,
    // as the new page a declarative router's list may show for that route.
    if ((_isNavigatingBack && !_isNewPageAtBackTarget(newState)) ||
        _isLastEntry(newState) ||
        _isStillUnderWaitingLink(newState)) {
      return;
    }
    if (_isRebuildingAfterPop) {
      // The last entry belongs to the popped page; drop it so back() can't
      // return to it, unless it left with its page. If the page now on top is
      // the entry before, _addEntry skips it as the same page.
      if (!isTopFree && _entries.isNotEmpty) _entries.removeLast();
      _addEntry(newState.copyWith(shouldReplace: false));
      return;
    }
    // A replace takes the place of the entry before, unless that entry just
    // left with its page: the place is then free.
    _addEntry(isTopFree ? newState.copyWith(shouldReplace: false) : newState);
  }

  // Whether [newState] shows the page that was on top before the link whose
  // entry is the last one, which no stack has held yet: the link is still on
  // its way, as when the page that holds a tabs router goes in anew before
  // its tab changes, and the screen shows nothing new. An entry here would
  // stay under the link's page once it lands, and back() would show the
  // page left twice.
  bool _isStillUnderWaitingLink(UrlState newState) {
    if (_entries case [..., final before, final last]
        when _linkPages.contains(last.pageId) &&
            !_wasOpen.contains(last) &&
            !_isOpen(last)) {
      return before.url == newState.url &&
          before.pageId == newState.topMatch?.id;
    }
    return false;
  }

  // Gives each page new on the way back under the page on top an entry of
  // its own, in its place among the others, as pages that pushAll or a
  // replaceAll of several pages open together: Flutter's Navigator closes
  // them one per pop. Pages a link opened together, the launch url included,
  // share the link's entry instead, as a page that turns up later under an
  // entry a link made, such as the first page of a nested router built a
  // frame after its page: the user made one navigation, and back() leaves it
  // as one. The same rules as the web's entry list.
  //
  // [top] is the page on top: the url state reported, or the one the stacks
  // show between reports.
  void _giveEntriesUnderTop(UrlState top) {
    final under = pagesUnderTop(router);
    final wayBack = [...under, top];
    _sharing.removeWhere((pageId, _) => controllerOfPage(pageId) == null);
    // A link's page not in yet, as one whose guard waits, keeps its mark
    // while its entry stays.
    _linkPages.removeWhere(
      (pageId) => controllerOfPage(pageId) == null && !_hasEntry(pageId),
    );
    if (_isNavigatingBack) return;
    _orderAsWayBack(wayBack);
    final isLink = router.root.isShowingLink;
    final topId = top.topMatch?.id;
    if (topId != null) {
      _sharing.remove(topId);
      if (isLink) _linkPages.add(topId);
    }
    for (final (place, page) in under.indexed) {
      final pageId = page.topMatch?.id;
      if (pageId == null ||
          _wayBackIds.contains(pageId) ||
          _sharing.containsKey(pageId) ||
          _hasEntry(pageId)) {
        continue;
      }
      // A page in the router that the page of a link goes in while a guard
      // there decides, as the first page of that router, went in with the
      // link: it shares the link's entry, also once a page the app pushes
      // meanwhile covers it.
      final linkPageId = _waitingLinkPageOver(page);
      if (linkPageId != null) {
        _sharing[pageId] = linkPageId;
        continue;
      }
      // The page on top has its entry, unless it shows no page.
      final overId = wayBack
          .skip(place + 1)
          .map((over) => over.topMatch?.id)
          .firstWhereOrNull((id) => id != null && _hasEntry(id));
      if (overId == null) continue;
      if (isLink || _linkPages.contains(overId)) {
        _sharing[pageId] = overId;
        continue;
      }
      // Right before the latest entry of the page over it: the page went in
      // with that page, so after any tab change made before, and back()
      // shows it next, as Navigator.pop does.
      final at = _entries.lastIndexWhere((entry) => entry.pageId == overId);
      final entry = _entryOf(page);
      _entries.insert(at, entry);
      _markIfHeld(entry);
    }
    // The oldest entries go first, as when entries are added one by one.
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  // The id of the page of a link that no stack has held yet, as one whose
  // guard decides, when that page goes in the router whose stack holds the
  // page on top of [page], or in a router nested in it.
  LocalKey? _waitingLinkPageOver(UrlState page) {
    final routerPageId = page.segments.reversed.elementAtOrNull(1)?.id;
    if (routerPageId == null) return null;
    return _entries
        .lastWhereOrNull(
          (entry) =>
              _linkPages.contains(entry.pageId) &&
              entry.pageId != routerPageId &&
              !_wasOpen.contains(entry) &&
              entry.route.flattened.any((match) => match.id == routerPageId),
        )
        ?.pageId;
  }

  // Puts the entries of the pages on [wayBack] in its order, in the places
  // those entries hold, as back() closes the pages in the order of the
  // stacks. A page whose entry was made before the page under it went in,
  // as one a guard let in after a push made meanwhile, would be skipped.
  // The entries of other pages, as of a tab not shown, keep their places.
  void _orderAsWayBack(List<UrlState> wayBack) {
    final places = <LocalKey, int>{
      for (final (place, page) in wayBack.indexed) ?page.topMatch?.id: place,
    };
    bool isOnWayBack(_HistoryEntry entry) => places.containsKey(entry.pageId);
    final onWayBack = _entries.where(isOnWayBack).toList();
    mergeSort(
      onWayBack,
      compare: (a, b) => places[a.pageId]!.compareTo(places[b.pageId]!),
    );
    final inOrder = onWayBack.iterator;
    final ordered = [
      for (final entry in _entries)
        if (isOnWayBack(entry) && inOrder.moveNext())
          inOrder.current
        else
          entry,
    ];
    _entries
      ..clear()
      ..addAll(ordered);
    // A page let in after its entry was made, as after a guard's sign-in
    // page, may also have reported its url anew: its two entries now meet.
    _mergeRepeatedEntries();
  }

  // Hands the entry of each page that has left from under the entry of
  // another page, and that pages of the way back shared, to the nearest of
  // them: it takes the entry's place with its own url, and the others that
  // shared it share it with that page. Otherwise those pages, as the pages a
  // link opened together, would lose their way back with the page that held
  // their entry. The same rule as the web's entry list.
  void _handOverSharedEntries() {
    if (_sharing.isEmpty) return;
    final wayBack = [...pagesUnderTop(router), urlState];
    for (final (place, entry) in _entries.indexed.toList()) {
      if (place == _entries.length - 1 ||
          !_wasOpen.contains(entry) ||
          _isOpen(entry)) {
        continue;
      }
      final heir = wayBack.lastWhereOrNull(
        (page) => _sharing[page.topMatch?.id] == entry.pageId,
      );
      final heirId = heir?.topMatch?.id;
      if (heir == null || heirId == null) continue;
      final heirEntry = _entryOf(heir);
      _entries[place] = heirEntry;
      _markIfHeld(heirEntry);
      _sharing
        ..remove(heirId)
        ..updateAll(
          (_, sharedId) => sharedId == entry.pageId ? heirId : sharedId,
        );
      _linkPages.add(heirId);
    }
  }

  bool _hasEntry(LocalKey pageId) =>
      _entries.any((entry) => entry.pageId == pageId);

  static _HistoryEntry _entryOf(UrlState state) =>
      .new(UrlState.toHierarchy(state.segments), state.url, state.topMatch!.id);

  // Drops the entries of the pages that have left their stacks, however they
  // left. A page leaves when it is popped or replaced, and also when the app
  // takes it off with removeLast, removeWhere, removeUntil, replaceAll or a
  // navigation to a page underneath. An entry whose page no stack has held
  // yet stays, as the entry of a link while a guard decides. Returns whether
  // the last entry was one of them.
  //
  // Like Flutter's Navigator.removeRoute, which disposes the route, so no
  // later pop returns to it, and the web history, which drops such entries on
  // every change.
  bool _dropClosed() {
    _handOverSharedEntries();
    final last = _entries.lastOrNull;
    _entries.removeWhere((entry) {
      if (_isOpen(entry)) {
        _markIfHeld(entry);
      } else if (_wasOpen.contains(entry)) {
        return true;
      }
      return !_wasOpen.contains(entry) && _isRefused(entry);
    });
    bool isKept(_HistoryEntry entry) =>
        _entries.any((kept) => identical(kept, entry));
    _wasOpen.retainWhere(isKept);
    _heldDepths.removeWhere((entry, _) => !isKept(entry));
    return last != null && !identical(_entries.lastOrNull, last);
  }

  // Whether the page [entry] stands for is still open: each page on the way
  // to it, from the root router down, is in the stack of the router that the
  // page before it holds. A router keeps a closed page's nested router among
  // its children until that page's widget is gone, so the way is followed
  // from the root. A page under one whose router isn't built yet, as the
  // first page of a nested router built a frame after its page, is open,
  // unless [isHeldOnly]: then only a page a stack holds is.
  bool _isOpen(_HistoryEntry entry, {bool isHeldOnly = false}) {
    RoutingController? controller = router;
    for (final match in entry.route.flattened) {
      if (controller == null || !controller.hasEntries) return !isHeldOnly;
      if (!controller.stackData.any((data) => data.route.id == match.id)) {
        return false;
      }
      // The way ends at the entry's own page: the route of a page whose
      // nested router was emptied still names the children it had.
      if (match.id == entry.pageId) return true;
      controller = controller.childControllers.lastWhereOrNull(
        (child) => child.matchId == match.id,
      );
    }
    return true;
  }

  // Whether the navigation that [entry], whose page no stack has held yet,
  // stands for can no longer land: a page on the way to it that a stack held
  // has left, as the page a guard's no takes back: a Navigator's history
  // holds only the pages it was given.
  bool _isRefused(_HistoryEntry entry) {
    final depth = _heldDepthOf(entry);
    final most = _heldDepths[entry] ?? 0;
    if (depth < most) return true;
    _heldDepths[entry] = depth;
    return false;
  }

  // How many pages of the way to [entry], from the root router down, stacks
  // hold.
  int _heldDepthOf(_HistoryEntry entry) {
    var depth = 0;
    RoutingController? controller = router;
    for (final match in entry.route.flattened) {
      if (controller == null ||
          !controller.stackData.any((data) => data.route.id == match.id)) {
        break;
      }
      depth++;
      if (match.id == entry.pageId) break;
      controller = controller.childControllers.lastWhereOrNull(
        (child) => child.matchId == match.id,
      );
    }
    return depth;
  }

  // Counts [entry] as once open when a stack holds its page. Not while the
  // way to it crosses a router not built yet: that router may be built
  // without the page, as when a guard there holds it out, and the entry
  // would then look like that of a page that closed.
  void _markIfHeld(_HistoryEntry entry) {
    if (_isOpen(entry, isHeldOnly: true)) _wasOpen.add(entry);
  }

  @override
  void rebuildUrlAfterPop({LocalKey? poppedPageId}) {
    if (poppedPageId != null) {
      // A page popped from under the page on top, as popUntil pops the pages
      // in between, leaves the url as it was, so the last entry stays; the
      // entries that showed the popped page go, or back() would reopen it.
      final last = _entries.lastOrNull;
      _entries.removeWhere(
        (entry) => !identical(entry, last) && entry.showsPage(poppedPageId),
      );
    }
    _isRebuildingAfterPop = true;
    try {
      rebuildUrl();
    } finally {
      _isRebuildingAfterPop = false;
    }
  }

  @override
  void rebuildUrlAfterClosingUnbuilt(Iterable<LocalKey> closedPageIds) {
    _entries.removeWhere((entry) => closedPageIds.any(entry.showsPage));
    // The page under a closed one may have reported its url again over the
    // closed page's entry, as the tabs page a turned-down link went on
    // through does.
    _mergeRepeatedEntries();
    rebuildUrl();
  }

  // Keeps one entry for a page where two entries in a row show it at the
  // same url, as a step back from one to the other would show nothing new.
  void _mergeRepeatedEntries() {
    final kept = <_HistoryEntry>[];
    for (final entry in _entries) {
      final before = kept.lastOrNull;
      if (before != null &&
          before.url == entry.url &&
          before.pageId == entry.pageId) {
        continue;
      }
      kept.add(entry);
    }
    _entries
      ..clear()
      ..addAll(kept);
  }

  @override
  bool get canNavigateBack => length > 1 && !_isNavigatingBack;

  @override
  int get length => _entries.length;

  // Whether [urlState] shows the page of the last entry.
  bool _isLastEntry(UrlState urlState) {
    final last = _entries.lastOrNull;
    return last != null &&
        last.url == urlState.url &&
        last.pageId == urlState.topMatch?.id;
  }

  void _addEntry(UrlState urlState) {
    if (!urlState.hasSegments) return;
    final newEntry = _entryOf(urlState);

    if (_isLastEntry(urlState)) return;
    // A page with the same url as the last entry's is a new entry only while
    // the last entry's page stays in a stack under it, as when the same route
    // is pushed twice. Otherwise it took that page's place, as navigate() does
    // with new arguments, or the router rebuilt its pages, so it takes the
    // entry.
    final last = _entries.lastOrNull;
    if (last != null &&
        last.url == urlState.url &&
        controllerOfPage(last.pageId) == null) {
      _entries.removeLast();
    }

    // Keeps room for the new entry within the limit.
    if (_entries.length >= _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries + 1);
    }
    if (urlState.shouldReplace && length > 0) {
      _entries.removeLast();
      // The entry before may already hold this url, e.g. the page a redirect
      // was shown for.
      if (_entries.lastOrNull?.url == urlState.url) return;
    }
    _entries.add(newEntry);
    _markIfHeld(newEntry);
  }

  @override
  void back() {
    _dropClosed();
    if (canNavigateBack) {
      _isNavigatingBack = true;
      final left = _entries.removeLast();

      final last = _entries.lastOrNull;
      if (last == null) {
        _isNavigatingBack = false;
        return;
      }

      // navigateAll completes only when the page it lands on is popped, which
      // may be during a later back(), so back navigation ends once the router
      // reports the entry's url, or when this navigation completes, if it is
      // still the latest.
      final backCount = ++_backCount;
      _backTargetUrl = last.url;
      _removePagesAboveWayTo(last);
      // Whether the guards on the way let the step in before the navigation
      // completed.
      var isLetIn = false;
      final navigation = router.navigateAllBack(
        [last.route],
        onLetIn: () {
          isLetIn = true;
          _takeStepBackLate(backCount, left, last);
        },
      );
      // The router shows the entry as the navigation returns, as it does when
      // no guard makes it wait, so this step back is done: a back() called
      // right after it takes the next step, as two calls of history.back() in
      // one task take a browser back two entries. A navigation that has not
      // started yet, as one called while widgets are built, is still to come.
      if (!router.hasNavigationWaitingToStart && _isLastEntry(urlState)) {
        _stopNavigatingBack();
      }
      unawaited(
        navigation.whenComplete(() {
          if (backCount != _backCount) return;
          // A step let in whose page is still on screen waits for the frame:
          // a declarative router hands it to the app's onNavigate, and the
          // app's list shows it only once it rebuilds the router, as a
          // Navigator's pages do.
          if (isLetIn && _isNavigatingBack && _showsPageOf(left)) {
            SchedulerBinding.instance
              ..addPostFrameCallback((_) => _endStepBack(backCount, left))
              ..ensureVisualUpdate();
            return;
          }
          _endStepBack(backCount, left);
        }),
      );
    }
  }

  // Whether [newState] shows, at the url back() goes to, a page with no
  // entry, while the page of that entry has left.
  bool _isNewPageAtBackTarget(UrlState newState) {
    final pageId = newState.topMatch?.id;
    return pageId != null &&
        newState.url == _backTargetUrl &&
        !_hasEntry(pageId) &&
        !_entries.any(
          (entry) =>
              entry.url == _backTargetUrl &&
              controllerOfPage(entry.pageId) != null,
        );
  }

  // Whether the page of [entry] is the page shown, at its url.
  bool _showsPageOf(_HistoryEntry entry) =>
      urlState.url == entry.url && urlState.topMatch?.id == entry.pageId;

  // Ends the step back numbered [backCount], from the page of [left], unless
  // a later back() has started. When the router never reported the entry's
  // url and still shows the page left, as when a guard rejects the step or
  // the app keeps the page in a declarative router's list, a refused
  // navigation changes nothing, so that page keeps its entry.
  void _endStepBack(int backCount, _HistoryEntry left) {
    if (backCount != _backCount) return;
    if (_isNavigatingBack &&
        _showsPageOf(left) &&
        !_entries.any((entry) => identical(entry, left))) {
      _entries.add(left);
    }
    _stopNavigatingBack();
  }

  // Takes off the pages above the page of [target], and when that page is
  // open, the pages above each page of the way to it too, as a page the app
  // pushed over the page that holds the router of [target]'s page: one
  // back() closes the page on top and shows the open page under it. Left to
  // the navigation that follows, they would wait for the guard it asks again
  // in that router, as the pages over an open page wait for a guard there,
  // and a guard that takes its time would keep them on screen.
  void _removePagesAboveWayTo(_HistoryEntry target) {
    if (_isOpen(target, isHeldOnly: true)) {
      for (final match in target.route.flattened) {
        removePagesAbove(match.id);
        if (match.id == target.pageId) return;
      }
    }
    removePagesAbove(target.pageId);
  }

  void _stopNavigatingBack() {
    _isNavigatingBack = false;
    _backTargetUrl = null;
  }

  // The step back numbered [backCount], from the page of [left] to that of
  // [target], is let in after back() has ended, as a step into a tab whose
  // guard decides later is: the tabs answer once their change has started,
  // so back() took the step for refused and put [left] back. The step is
  // taken after all, so the next back() goes one step further, as when the
  // guard answers at once: [left] leaves, and the page of [target] keeps one
  // entry. Only when it is that step that lands, on the page of [target],
  // and [left] is still where back() put it, on top or under the entries
  // the page of [target] has reported since. Nothing changes when the user
  // picked another tab meanwhile, whose change called the step off, or a
  // page went on over [left]: the way back goes through it, as Flutter's
  // Route.didPopNext makes a page current again once the page over it is
  // popped. Nor when a later back() has started, or when [left] is no
  // longer an entry, as when the step was taken in time.
  //
  // Decided once the frame ends: a page the guard showed while it decided,
  // as the sign-in page of redirectUntil, leaves as the guard lets the step
  // in.
  void _takeStepBackLate(
    int backCount,
    _HistoryEntry left,
    _HistoryEntry target,
  ) {
    // A step let in before back() ended put nothing back: nothing to do.
    if (backCount != _backCount ||
        !_entries.any((entry) => identical(entry, left))) {
      return;
    }
    SchedulerBinding.instance
      ..addPostFrameCallback(
        (_) => _settleStepBackLate(backCount, left, target),
      )
      ..ensureVisualUpdate();
  }

  void _settleStepBackLate(
    int backCount,
    _HistoryEntry left,
    _HistoryEntry target,
  ) {
    if (backCount != _backCount) return;
    final shown = UrlState.fromSegments(router.currentSegments);
    if (shown.url != target.url || shown.topMatch?.id != target.pageId) {
      return;
    }
    final at = _entries.lastIndexWhere((entry) => identical(entry, left));
    if (at == -1) return;
    final isLeftWhereBackPutIt = _entries
        .skip(at + 1)
        .every(
          (entry) => entry.url == target.url && entry.pageId == target.pageId,
        );
    if (!isLeftWhereBackPutIt) return;
    _entries.removeAt(at);
    _mergeRepeatedEntries();
  }

  @override
  void forward() {
    throw FlutterError(
      'forward navigation is not supported for non-web platforms',
    );
  }

  @override
  Object get pathState =>
      throw FlutterError('pathState is not supported for non-web platforms');

  @override
  void pushPathState(Object? state) {
    throw FlutterError('pushPathState is not supported for non-web platforms');
  }
}

@immutable
class _HistoryEntry {
  const new(this.route, this.url, this.pageId);
  final RouteMatch<Object?> route;
  final String url;

  // The id of the page on top, which tells apart two pages with the same url.
  final LocalKey pageId;

  // Whether this entry showed the page with [id], on top or holding the
  // router of the page on top.
  bool showsPage(LocalKey id) => route.flattened.any((match) => match.id == id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _HistoryEntry &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() {
    return route.flattened.map((e) => e.name).join('->');
  }
}
