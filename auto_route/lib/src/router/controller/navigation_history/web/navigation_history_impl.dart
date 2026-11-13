import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/utils.dart';
import 'package:flutter/foundation.dart' show LocalKey;
import 'package:flutter/widgets.dart'
    show RouteInformation, RouteInformationProvider, Router;
import 'package:web/web.dart';

/// An implementation of [NavigationHistory]
/// That's used for web
class NavigationHistoryImpl extends NavigationHistory {
  /// Default constructor
  new(this.router);

  @override
  final StackRouter router;

  final History _history = window.history;

  // The url state of each browser entry, by the engine's serial count. The
  // browser exposes only its current entry, so each entry is recorded when the
  // app writes it and checked again whenever the browser shows it.
  final _entries = <int, UrlState>{};

  // The serial count of the entry that holds the app's current url, as far as
  // known.
  int? _appIndex;

  // The url of the entry this history moved the browser to, until the browser
  // reports it.
  String? _ownMoveUrl;

  // Whether a pop is going back to an entry the browser holds: the change
  // takes that entry, and records none of its own.
  bool _isSteppingBack = false;

  // The entry a step back after a pop waits to move the browser to, or null.
  // Used only while no frame is accounted for (see [_startFrame]).
  int? _stepBackTarget;

  bool _doesAddEntryWithSameUrl = false;

  // The browser's entries as this turn found them, by serial count, or null
  // outside a turn's changes. During a turn every change only records the
  // entries the app's pages ask for; when the turn ends, [_reconcile] brings
  // the browser from these to those in one go.
  Map<int, UrlState>? _frameStartEntries;

  // The entry the browser stood on when this turn's changes started.
  int _frameStartIndex = 0;

  // Whether the end of this turn's account is scheduled.
  bool _isEndScheduled = false;

  // What to write once the browser reports the step back that the end of a
  // turn made, each with whether it replaces the entry the browser is on.
  List<(UrlState, bool)> _writesAfterMove = const [];

  @override
  bool get addsEntryWithSameUrl => _doesAddEntryWithSameUrl;

  @override
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    final browserIndex = _currentIndex;
    final browserPath = ui_web.urlStrategy?.getPath();
    _recordCurrentEntry();
    final isNewUrl = !_isSameUrl(urlState.url, newState.url);
    // A page pushed over one with the same url gets a browser entry of its own,
    // so that going back returns to the page under it.
    final isPushedOverSameUrl =
        !isNewUrl &&
        !_isSteppingBack &&
        !_isPageOfEntry(browserIndex, newState) &&
        _isPushedOverSameUrl(newState);
    // The browser moved first, by its own buttons or the address bar; with
    // the same url, to the entry of another page that has it. While a turn's
    // changes wait for its end, the browser still shows the url it showed when
    // the turn began, which a page pushed again may share; that is no move.
    final didBrowserMoveFirst =
        !isPushedOverSameUrl &&
        _isSameUrl(browserPath, newState.url) &&
        (isNewUrl || browserIndex != _appIndex) &&
        (_frameStartEntries == null || browserIndex != _frameStartIndex);
    // A page with the same url as the app entry's page, which has left, takes
    // its place, as pushAndPopUntil's new page that of the pages it closed. A
    // page that some entry holds already, as when the browser went back to the
    // closed page's entry, needs none of its own.
    final appEntryPage = _entries[_appIndex]?.topMatch?.id;
    final newPage = newState.topMatch?.id;
    final isNewPage =
        !_entries.values.any((entry) => entry.topMatch?.id == newPage) &&
        !isNewUrl &&
        appEntryPage != null &&
        newPage != null &&
        newPage != appEntryPage &&
        _isSameUrl(_entries[_appIndex]?.url, newState.url) &&
        controllerOfPage(appEntryPage) == null;
    // The app's first url, when it differs from the one the browser was opened
    // at, as one written without an empty query value, takes that entry.
    final reported = _appIndex == null && notify && !didBrowserMoveFirst
        ? newState.copyWith(shouldReplace: true)
        : newState;
    final hasFrame = notify && _startFrame();
    // Outside a turn's account, a step back moves the browser itself, which
    // reports the url once it gets there; a notification now would make the
    // router write it as a new entry. Within one, the end of the turn makes the
    // move, and the router's report only repeats the entry on top (see
    // [writesBrowserEntries]).
    final doesNotify = notify && (!_isSteppingBack || hasFrame);
    _doesAddEntryWithSameUrl = doesNotify && isPushedOverSameUrl;
    try {
      super.onNewUrlState(reported, notify: doesNotify);
    } finally {
      _doesAddEntryWithSameUrl = false;
    }
    if (_isSteppingBack) return;
    if (didBrowserMoveFirst) {
      _entries[browserIndex] = newState;
      _appIndex = browserIndex;
      // The browser holds this entry already, and stands on it.
      _frameStartEntries?[browserIndex] = newState;
      if (_frameStartEntries != null) _frameStartIndex = browserIndex;
    } else if (notify && (isNewUrl || isPushedOverSameUrl || isNewPage)) {
      final appIndex = _appIndex;
      _record(
        newState,
        appIndex == null
            ? browserIndex
            : appIndex + (newState.shouldReplace ? 0 : 1),
      );
    }
  }

  // Records [newState] as the entry the app's pages ask for at [index], over
  // the app's entry or as the next one; the entries after it are gone, as the
  // browser drops those after a new one.
  void _record(UrlState newState, int index) {
    _startFrame();
    _entries.removeWhere((key, _) => key >= index);
    _entries[index] = newState;
    _appIndex = index;
  }

  // Starts this turn's account of the browser, unless it has started, and
  // returns whether there is one. The router writes the url once a frame,
  // after it: only the app's entry, with one kind for the whole frame, since
  // the Router keeps the first neglect or navigate it is given. So the history
  // writes the entries of a turn's changes itself when the turn ends, and the
  // router's own write of them is then left out, which only
  // AutoRouteInformationProvider can do. Before a Router shows this history
  // there is nothing to account for, as when an app navigates before runApp.
  bool _startFrame() {
    if (_frameStartEntries == null) {
      if (!isShownByRouter || _provider == null) return false;
      _frameStartEntries = Map.of(_entries);
      _frameStartIndex = _appIndex ?? _currentIndex;
    }
    if (!_isEndScheduled) {
      _isEndScheduled = true;
      scheduleMicrotask(_endFrame);
    }
    return true;
  }

  // The route information provider of the Router that shows this history.
  RouteInformationProvider? get _provider {
    final context = router.navigatorKey.currentContext;
    if (context == null) return null;
    return Router.maybeOf<Object?>(context)?.routeInformationProvider;
  }

  @override
  bool get writesBrowserEntries => _frameStartEntries != null;

  // Ends this turn's account: brings the browser to the entries the app's
  // pages ask for.
  void _endFrame() {
    _isEndScheduled = false;
    // While the app shows no page, as between the pages pushAndPopUntil takes
    // off and the one it puts on, the account stays open for the next turn.
    if (!urlState.hasSegments) return;
    // A step back of an earlier turn is still on its way: this turn's account
    // waits for the browser to land (see consumeOwnBrowserMove).
    if (_ownMoveUrl != null) return;
    final start = _frameStartEntries;
    _frameStartEntries = null;
    final provider = _provider;
    if (start == null || provider == null) return;
    _reconcile(start, _frameStartIndex, provider);
  }

  // Brings the browser from the entries it held at the frame's start, [start],
  // standing on [standsOn], to the entries the app's pages ask for now, in one
  // place, so that any calls in one turn end where the same calls a frame
  // apart end: it keeps what the two share from the bottom, steps back over
  // what is no longer there, writes what is new, and writes the top as a
  // replace when only the entry on top changed. An entry this turn added
  // whose page is gone again was never shown, and gets none. Afterwards the
  // account holds only what the browser holds, also when nothing was written.
  void _reconcile(
    Map<int, UrlState> start,
    int standsOn,
    RouteInformationProvider provider,
  ) {
    final appIndex = _appIndex;
    if (appIndex == null) return;
    final neglects = provider is AutoRouteInformationProvider
        ? provider.neglectIf
        : null;
    // The entries the app's pages ask for, from the bottom; null for an entry
    // of the browser's that the history doesn't know and keeps as it is.
    final wanted = <UrlState?>[];
    for (var i = 0; i <= appIndex; i++) {
      final entry = _entries[i];
      final isKept = i <= standsOn && _isSameEntry(entry, start[i]);
      if (entry == null) {
        if (isKept) wanted.add(null);
        continue;
      }
      if (!isKept) {
        final location = entry.url.isEmpty ? '/' : entry.uri.toString();
        if (!_isShown(entry) || (neglects?.call(location) ?? false)) continue;
        // A new entry that repeats the one under it adds nothing; one that
        // takes the place of an entry the browser holds stays a replace.
        if (i > standsOn && _isSameEntry(wanted.lastOrNull, entry)) continue;
      }
      wanted.add(entry);
    }
    final top = wanted.length - 1;
    var shared = 0;
    for (final (index, entry) in wanted.indexed) {
      if (index > standsOn || !_isSameEntry(entry, start[index])) break;
      shared++;
    }
    if (top < 0) return;
    final isUnchanged = shared == wanted.length && top == standsOn;

    // From where the browser stands: a step back, if any, then the writes,
    // and the entries the browser then holds, from the bottom.
    var moveTo = standsOn;
    var replacesFirst = false;
    final holds = wanted;
    if (shared > top) {
      // What the app asks for is what the browser holds under where it stands.
      moveTo = top;
    } else if (shared == standsOn) {
      // Only the entry on top changed.
      replacesFirst = true;
    } else if (shared == 0) {
      // Nothing is shared: a step back to the bottom entry, which the first
      // entry the app asks for replaces.
      moveTo = 0;
      replacesFirst = true;
    } else if (shared < standsOn) {
      // A step back to the last entry they share, then each new entry in turn,
      // which drops the browser's entries after it, as new entries do.
      moveTo = shared - 1;
    }
    final writes = [
      for (final (index, entry) in wanted.indexed.skip(shared))
        if (entry != null) (entry, replacesFirst && index == shared),
    ];

    // A new entry drops those after it; a step back or a replace keeps them
    // ahead, for the browser's forward button.
    final keepsAhead = writes.every((write) => write.$2);
    _entries
      ..clear()
      ..addAll({
        for (final MapEntry(:key, :value) in start.entries)
          if (keepsAhead && key >= holds.length) key: value,
        for (final (index, entry) in holds.indexed)
          index: ?(entry ?? start[index]),
      });
    _appIndex = holds.length - 1;

    if (isUnchanged) return;
    // Steps are counted from the entry the browser really stands on, which
    // differs from the account where the browser holds entries the app didn't
    // write. Only a step backwards is made: any other reloads or leaves.
    final steps = moveTo - _currentIndex;
    if (moveTo < standsOn && steps < 0) {
      _ownMoveUrl = start[moveTo]?.url;
      _writesAfterMove = writes;
      _history.go(steps);
      return;
    }
    // The router reports the turn's url after the frame as a replace of the
    // entry on top (AutoRouterDelegate): a replace of that entry with the
    // app's url is left to it, so that the url goes out once.
    if (writes.lastOrNull case (final entry, true)
        when _isSameEntry(entry, urlState)) {
      writes.removeLast();
    }
    writes.forEach(_write);
  }

  // Whether a stack holds the page on top of [entry], or the page whose nested
  // router is not built yet, so that its children, the entry's own pages, are
  // still to come: a page this turn pushes opens its nested router when it
  // builds, after the turn.
  bool _isShown(UrlState entry) {
    final matches = entry.segments;
    for (final (index, match) in matches.indexed.toList().reversed) {
      final holder = controllerOfPage(match.id);
      if (holder == null) continue;
      return index == matches.length - 1 ||
          !holder.childControllers.any(
            (child) => child.routeData.matchId == match.id,
          );
    }
    return false;
  }

  // Whether [a] and [b] are the same browser entry: the same url, page on top
  // and path state.
  bool _isSameEntry(UrlState? a, UrlState? b) {
    if (a == null || b == null) return identical(a, b);
    return _isSameUrl(a.url, b.url) &&
        a.topMatch?.id == b.topMatch?.id &&
        a.pathState == b.pathState;
  }

  // Writes [write]'s entry to the browser, over the entry it stands on or as
  // a new one, through the Router's own parser and provider, so neglectWhen
  // still applies.
  void _write((UrlState, bool) write) {
    final (entry, replaces) = write;
    // The entry's own replace mark would make the provider replace.
    final information = _informationOf(entry.copyWith(shouldReplace: replaces));
    if (information == null) return;
    _provider?.routerReportsNewRouteInformation(
      information,
      type: replaces ? .neglect : .navigate,
    );
  }

  // The route information the Router's own parser makes of [entry].
  RouteInformation? _informationOf(UrlState entry) {
    final context = router.navigatorKey.currentContext;
    if (context == null) return null;
    return Router.maybeOf<Object?>(context)?.routeInformationParser
        ?.restoreRouteInformation(entry);
  }

  @override
  // The browser can't delete an entry, so a page popped from under the page
  // on top keeps its entry here. A page taken off the stack without a pop,
  // with no [poppedPageId], as by pushAndPopUntil, steps back one entry at
  // most.
  void rebuildUrlAfterPop({LocalKey? poppedPageId}) {
    final isPop = poppedPageId != null;
    final popped = urlState;
    final newState = UrlState.fromSegments(router.currentSegments);
    final newUrl = newState.url;
    final isSameUrl = newUrl == popped.url;
    _recordCurrentEntry();
    final hasFrame = _startFrame();
    // The pops of one turn come one after another, before the browser has
    // made the step back of the one before: the app's entry counts as
    // current.
    final index = hasFrame || (isPop && _stepBackTarget != null)
        ? (_appIndex ?? _currentIndex)
        : _currentIndex;
    // Whether the entry at index i holds the page on top of [state]; two pages
    // with the same url, pushed one over the other, are told apart by page.
    bool doesHold(int i, UrlState state) {
      final entry = _entries[i];
      return entry != null &&
          _isSameUrl(entry.url, state.url) &&
          (!isSameUrl || entry.topMatch?.id == state.topMatch?.id);
    }

    final target = !doesHold(index, popped)
        ? null
        : isPop
        ? _entryBeforeClosedPages(index, (i) => doesHold(i, newState))
        : (index > 0 && doesHold(index - 1, newState) ? index - 1 : null);
    if (target != null) {
      _isSteppingBack = true;
      try {
        rebuildUrl();
      } finally {
        _isSteppingBack = false;
      }
      _appIndex = target;
      // Within a frame its end steps the browser back; outside one, the step
      // is made here.
      if (hasFrame) return;
      _ownMoveUrl = newUrl;
      if (isPop) {
        _scheduleStepBack(target);
      } else {
        _history.back();
      }
      return;
    }
    if (isSameUrl) {
      // The popped page wasn't part of the url, or had no entry of its own.
      rebuildUrl();
      return;
    }
    // The entry before belongs to another page, so the page now on top takes
    // the popped page's entry.
    markUrlStateForReplace();
    rebuildUrl();
  }

  // Steps the browser back to [target] once the pops being made now are done,
  // in one move: the browser makes a move later, and reports each one. A later
  // pop of the same turn moves the target on. Only outside a frame; within
  // one, [_reconcile] makes the move.
  void _scheduleStepBack(int target) {
    final isScheduled = _stepBackTarget != null;
    _stepBackTarget = target;
    if (isScheduled) return;
    scheduleMicrotask(() {
      final to = _stepBackTarget;
      _stepBackTarget = null;
      if (to == null) return;
      final steps = to - _currentIndex;
      if (steps < 0) _history.go(steps);
    });
  }

  // The nearest entry before [index] for which [isTarget] holds, when every
  // entry between holds a page that no stack holds any more, as the pages
  // StackRouter.popUntil closes at once leave them. Null otherwise.
  int? _entryBeforeClosedPages(int index, bool Function(int i) isTarget) {
    for (var i = index - 1; i >= 0; i--) {
      if (isTarget(i)) return i;
      final pageId = _entries[i]?.topMatch?.id;
      if (pageId == null || controllerOfPage(pageId) != null) return null;
    }
    return null;
  }

  @override
  bool consumeOwnBrowserMove(UrlState configuration) {
    final ownMoveUrl = _ownMoveUrl;
    final writes = _writesAfterMove;
    _ownMoveUrl = null;
    _writesAfterMove = const [];
    final isOwn =
        ownMoveUrl != null && _isSameUrl(configuration.url, ownMoveUrl);
    // The step back of a turn's end has landed; the entries after it follow,
    // then the account of a later turn that waited for it.
    if (isOwn) writes.forEach(_write);
    if (_frameStartEntries != null && !_isEndScheduled) {
      _isEndScheduled = true;
      scheduleMicrotask(_endFrame);
    }
    return isOwn;
  }

  @override
  List<RouteMatch<Object?>>? routesOfBrowserEntry(UrlState configuration) {
    final entry = _entries[_currentIndex];
    if (entry == null ||
        !entry.hasSegments ||
        !_isSameUrl(entry.url, configuration.url)) {
      return null;
    }
    final pageId = entry.topMatch?.id;
    // The entry's page may still be under the current one with the same route
    // name, as when the same route was pushed twice, with the same params or
    // others; navigating to it alone would update the current page in place.
    if (pageId != null) {
      removePagesAbove(pageId);
      // The same page can show another url, as when its query params changed
      // in place; then the entry still needs to be shown.
      if (router.topMatch.id == pageId && _isSameUrl(urlState.url, entry.url)) {
        _takeOverEntryState(configuration.pathState);
        return const [];
      }
    }
    return [UrlState.toHierarchy(entry.segments)];
  }

  @override
  (StackRouter, RouteMatch<Object?>)? pageToPushForBrowserEntry(
    UrlState configuration,
  ) {
    final appIndex = _appIndex;
    final index = _currentIndex;
    final entry = _entries[index];
    final page = entry?.topMatch;
    final currentPageId = urlState.topMatch?.id;
    if (appIndex == null ||
        index != appIndex + 1 ||
        page == null ||
        currentPageId == null) {
      return null;
    }
    if (!_isSameUrl(entry!.url, configuration.url) ||
        !_isSameUrl(urlState.url, entry.url)) {
      return null;
    }
    if (page.id == currentPageId || controllerOfPage(page.id) != null) {
      return null;
    }
    final holder = controllerOfPage(currentPageId);
    return holder is StackRouter ? (holder, page) : null;
  }

  @override
  bool get isBrowserBehindApp {
    final appIndex = _appIndex;
    final index = _currentIndex;
    if (appIndex == null || index >= appIndex) return false;
    // An entry of the page on top, as one before a pushPathState entry, closes
    // no page: like the browser moving between two states of one document, it
    // asks no PopScope.
    final entry = _entries[index];
    final pageId = urlState.topMatch?.id;
    return entry == null ||
        pageId == null ||
        entry.topMatch?.id != pageId ||
        !_isSameUrl(entry.url, urlState.url);
  }

  @override
  void returnBrowserToApp() {
    final appIndex = _appIndex;
    if (appIndex == null || _currentIndex >= appIndex) return;
    _ownMoveUrl = urlState.url;
    _history.go(appIndex - _currentIndex);
  }

  // Records the app's current url state for the current browser entry, if
  // the browser shows that url and, as far as known, the app's entry: an entry
  // the browser moved to may hold another page with the same url.
  void _recordCurrentEntry() {
    if (!_isSameUrl(ui_web.urlStrategy?.getPath(), urlState.url)) return;
    final index = _currentIndex;
    if (_appIndex != null && _appIndex != index) return;
    _entries[index] = urlState;
    _appIndex = index;
  }

  // Whether the browser entry at [index], which the browser moved to, holds the
  // page on top of [state], as when its forward button reopens a page pushed
  // over one with the same url.
  bool _isPageOfEntry(int index, UrlState state) {
    final pageId = state.topMatch?.id;
    return index != _appIndex &&
        pageId != null &&
        _entries[index]?.topMatch?.id == pageId;
  }

  // Whether [newState] shows a page pushed over the app's current page with the
  // same url, which stays in a stack under it.
  bool _isPushedOverSameUrl(UrlState newState) {
    final currentPageId = urlState.topMatch?.id;
    return currentPageId != null &&
        newState.topMatch?.id != currentPageId &&
        controllerOfPage(currentPageId) != null;
  }

  bool _isSameUrl(String? a, String b) {
    if (a == null) return false;
    // Decoding throws on a letter outside ASCII, which a decoded url can hold,
    // so parsing first encodes it again. Escaped bytes that aren't valid UTF-8
    // read as U+FFFD, as the matcher reads them.
    String normalize(String url) =>
        url.isEmpty ? '/' : decodeUrlComponent(Uri.parse(url).toString());
    return normalize(a) == normalize(b);
  }

  /// Steps the browser back one entry, unless the app's first entry is current.
  ///
  /// The tab may hold pages from before the app, such as the site the user
  /// came from; stepping back from the app's first entry would leave the app.
  @override
  void back() {
    if (canNavigateBack) _history.back();
  }

  int get _currentIndex {
    final state = _history.state.dartify();
    if (state is Map) {
      final serialCount = state['serialCount'];
      if (serialCount is num) {
        return serialCount.toInt();
      }
    }
    return 0;
  }

  @override
  bool get canNavigateBack => _currentIndex > 0;

  @override
  void forward() => _history.forward();

  /// The number of the app's browser entries up to and including the current
  /// one.
  ///
  /// Counts by the engine's serial count, which starts at the app's first
  /// entry, so pages from before the app and entries ahead of the current one
  /// are left out.
  @override
  int get length => _currentIndex + 1;

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
    final index = (_appIndex ?? _currentIndex) + 1;
    onNewUrlState(newState);
    // The url stays the same, so onNewUrlState records no entry for it.
    _record(newState, index);
  }

  // The browser moved to an entry whose page the app already shows, as its
  // back button does from an entry made by [pushPathState]: the app takes
  // over the entry's state, [entryState], null included, so the router
  // reports what the entry holds and the browser keeps the entries ahead of
  // it.
  void _takeOverEntryState(Object? entryState) {
    final shown = UrlState(
      urlState.uri,
      urlState.segments,
      pathState: entryState,
    );
    super.onNewUrlState(shown, notify: false);
    _entries[_currentIndex] = shown;
    _appIndex = _currentIndex;
  }

  @override
  Object? get pathState => urlState.pathState;
}
