import 'dart:async';

import 'package:auto_route/auto_route.dart'
    show RouteMatch, RoutingController, StackRouter, UrlState;
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart'
    show pagesUnderTop;
import 'package:auto_route/src/router/controller/navigation_history/browser/history_entry_list.dart'
    show isSameHistoryUrl;
import 'package:auto_route/src/router/controller/navigation_history/navigation_history.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

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
    // Don't add entries during back navigation to prevent duplicates
    if (_isNavigatingBack || _isLastEntry(newState)) return;
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
        return false;
      }
      return _wasOpen.contains(entry);
    });
    _wasOpen.retainWhere(
      (entry) => _entries.any((kept) => identical(kept, entry)),
    );
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
    // The page under a closed one may have reported its url again over the
    // closed page's entry, as the tabs page a turned-down link went on
    // through does: the page keeps one entry, as a step back to the same
    // page shows nothing new.
    final kept = <_HistoryEntry>[];
    for (final entry in _entries) {
      if (closedPageIds.any(entry.showsPage)) continue;
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
    rebuildUrl();
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
      removePagesAbove(last.pageId);
      final navigation = router.navigateAll([last.route]);
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
          // The router never reported the entry's url and still shows the
          // page left, as when a guard rejects it: a refused navigation
          // changes nothing, so that page keeps its entry.
          if (_isNavigatingBack &&
              urlState.url == left.url &&
              urlState.topMatch?.id == left.pageId) {
            _entries.add(left);
          }
          _stopNavigatingBack();
        }),
      );
    }
  }

  void _stopNavigatingBack() {
    _isNavigatingBack = false;
    _backTargetUrl = null;
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
