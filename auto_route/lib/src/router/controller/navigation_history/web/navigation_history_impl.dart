import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart' show LocalKey;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart' show Router;
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

  bool _isSteppingBack = false;

  // Whether a step back after a pop waits to be made, to [_appIndex].
  bool _isStepBackScheduled = false;

  bool _doesAddEntryWithSameUrl = false;

  // The entry a navigation of this frame adds, which the router writes only
  // when the frame ends, or null.
  int? _unwrittenIndex;

  // Whether the app's entry is one the router has yet to write.
  bool get _isAppEntryUnwritten =>
      _unwrittenIndex != null && _unwrittenIndex == _appIndex;

  @override
  bool get addsEntryWithSameUrl => _doesAddEntryWithSameUrl;

  @override
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    // The router writes the url once a frame, with the last change's kind. A
    // replace of the entry an earlier navigation of this frame adds goes to
    // the browser as that new entry, or it would replace the one under; it
    // still takes that entry's place here.
    final isReplace = newState.shouldReplace;
    _onNewUrlState(
      isReplace && _isAppEntryUnwritten
          ? newState.copyWith(shouldReplace: false)
          : newState,
      notify: notify,
      isReplace: isReplace,
    );
  }

  void _onNewUrlState(
    UrlState newState, {
    required bool notify,
    required bool isReplace,
  }) {
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
    _doesAddEntryWithSameUrl = notify && isPushedOverSameUrl;
    try {
      // While stepping back, the browser reports the new url once it gets
      // there. A notification now would make the router write it as a new
      // entry.
      super.onNewUrlState(newState, notify: notify && !_isSteppingBack);
    } finally {
      _doesAddEntryWithSameUrl = false;
    }
    if (_isSteppingBack) return;
    if (!isPushedOverSameUrl &&
        _isSameUrl(browserPath, newState.url) &&
        (isNewUrl || browserIndex != _appIndex)) {
      // The browser moved first, by its own buttons or the address bar; with
      // the same url, to the entry of another page that has it.
      _entries[browserIndex] = newState;
      _appIndex = browserIndex;
    } else if (notify && (isNewUrl || isPushedOverSameUrl)) {
      _recordEntryToWrite(newState, browserIndex, isReplace: isReplace);
    }
  }

  // The router writes [newState] after this frame: over the current entry for
  // a replace, [isReplace], otherwise as a new entry, which drops those after
  // it.
  void _recordEntryToWrite(
    UrlState newState,
    int browserIndex, {
    required bool isReplace,
  }) {
    // Two navigations of one frame that each add an entry get one each, as two
    // history.pushState calls do; the router would write only the last.
    if (!isReplace && _isAppEntryUnwritten) _writeAppEntryNow();
    final index = (_appIndex ?? browserIndex) + (isReplace ? 0 : 1);
    _entries.removeWhere((key, _) => key >= index);
    _entries[index] = newState;
    _appIndex = index;
    if (isReplace) return;
    final isFirstOfFrame = _unwrittenIndex == null;
    _unwrittenIndex = index;
    // The router has written every entry of the frame once it ends.
    if (isFirstOfFrame) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _unwrittenIndex = null,
      );
    }
  }

  // Writes the app's entry, which the router has yet to write, as a new
  // browser entry now, through the Router's own parser and provider, so
  // neglectWhen still applies. Only while a stack still holds its page, as
  // the first of two pushes stays under the second: a page that left before
  // it showed, such as a guarded page that redirected at once, gets no entry.
  // Does nothing before the router is built.
  void _writeAppEntryNow() {
    final entry = _entries[_appIndex];
    final pageId = entry?.topMatch?.id;
    final context = router.navigatorKey.currentContext;
    if (entry == null ||
        context == null ||
        pageId == null ||
        controllerOfPage(pageId) == null) {
      return;
    }
    final shownBy = Router.maybeOf<Object?>(context);
    final information = shownBy?.routeInformationParser
        ?.restoreRouteInformation(entry);
    if (information == null) return;
    shownBy!.routeInformationProvider?.routerReportsNewRouteInformation(
      information,
      type: .navigate,
    );
  }

  @override
  // The browser can't delete an entry, so a page popped from under the page
  // on top keeps its entry here. A page taken off the stack without a pop,
  // with no [poppedPageId], as by pushAndPopUntil, steps back one entry at
  // most, at once.
  void rebuildUrlAfterPop({LocalKey? poppedPageId}) {
    final isPop = poppedPageId != null;
    final popped = urlState;
    final newState = UrlState.fromSegments(router.currentSegments);
    final newUrl = newState.url;
    final isSameUrl = newUrl == popped.url;
    _recordCurrentEntry();
    // The pops of one popUntil come one after another, before the browser has
    // made the step back of the one before; that step's entry counts as
    // current.
    final index = isPop && _isStepBackScheduled
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
      _ownMoveUrl = newUrl;
      if (isPop) {
        _scheduleStepBack();
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

  // Steps the browser back to [_appIndex] once the pops being made now are
  // done, in one move: the browser makes a move later, and reports each one.
  void _scheduleStepBack() {
    if (_isStepBackScheduled) return;
    _isStepBackScheduled = true;
    scheduleMicrotask(() {
      _isStepBackScheduled = false;
      final steps = (_appIndex ?? _currentIndex) - _currentIndex;
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
    _ownMoveUrl = null;
    return ownMoveUrl != null && _isSameUrl(configuration.url, ownMoveUrl);
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
    // Uri.decodeFull throws on a letter outside ASCII, which a decoded url can
    // hold; parsing first encodes it again.
    String normalize(String url) =>
        url.isEmpty ? '/' : Uri.decodeFull(Uri.parse(url).toString());
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
    final browserIndex = _currentIndex;
    onNewUrlState(newState);
    // The url stays the same, so onNewUrlState records no entry for it.
    _recordEntryToWrite(newState, browserIndex, isReplace: false);
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
