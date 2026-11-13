import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/utils.dart';
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

  // The entry a step back after a pop waits to move the browser to, or null.
  int? _stepBackTarget;

  bool _doesAddEntryWithSameUrl = false;

  // What this frame has done to the browser so far, until the frame ends. The
  // router writes the url once a frame, after it: only the app's entry, and
  // with one kind for the whole frame, since the Router keeps the first
  // neglect or navigate it is given. These tell what that one write can't do.
  //
  // The entry the browser stands on once the entries written so far this
  // frame are in, or null outside a frame.
  int? _frameBrowserIndex;

  // The entry this frame recorded that only the router's write will put in,
  // or null.
  int? _pendingIndex;

  // Whether the router writes this frame's url over the browser's entry, as
  // a change it reported as a replace makes it, or as a new entry, as a page
  // pushed over one with the same url makes it.
  bool _doesFrameReplace = false;
  bool _doesFrameNavigate = false;

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
    // the same url, to the entry of another page that has it.
    final didBrowserMoveFirst =
        !isPushedOverSameUrl &&
        _isSameUrl(browserPath, newState.url) &&
        (isNewUrl || browserIndex != _appIndex);
    // While stepping back, the browser reports the new url once it gets
    // there. A notification now would make the router write it as a new
    // entry.
    final doesNotify = notify && !_isSteppingBack;
    final records =
        doesNotify && !didBrowserMoveFirst && (isNewUrl || isPushedOverSameUrl);
    final backTo = records && !newState.shouldReplace
        ? _entryUnderUnshownPage(newState)
        : null;
    final index =
        backTo ??
        ((_appIndex ?? browserIndex) + (newState.shouldReplace ? 0 : 1));
    final reported = backTo != null
        ? _stepBackTo(backTo, newState)
        : records
        ? _placeEntry(newState, index)
        : newState;
    _doesAddEntryWithSameUrl = doesNotify && isPushedOverSameUrl;
    try {
      super.onNewUrlState(reported, notify: doesNotify);
    } finally {
      _doesAddEntryWithSameUrl = false;
    }
    if (doesNotify) {
      _noteReport(reported, isPushedOverSameUrl: isPushedOverSameUrl);
    }
    if (_isSteppingBack) return;
    if (didBrowserMoveFirst) {
      _entries[browserIndex] = newState;
      _appIndex = browserIndex;
      if (_frameBrowserIndex != null) _frameBrowserIndex = browserIndex;
    } else if (records) {
      _recordEntry(reported, index);
    }
  }

  // Readies the browser for the entry [newState] at [index], before the router
  // hears of it, and returns the state to report: with the kind the router's
  // one write needs, a replace when [index] is the entry the browser stands
  // on, a new entry when it is the next one. Every pair of changes in a frame
  // comes down to these, as the history API's calls one after another do: an
  // entry recorded earlier in the frame is written now, and a pop of the frame
  // that this entry follows needs no step back of its own.
  UrlState _placeEntry(UrlState newState, int index) {
    if (!_startFrame()) return newState;
    final pending = _pendingIndex;
    if (pending != null && pending != index) _writeEntryNow(pending);
    final standsOn = _frameBrowserIndex!;
    if (_stepBackTarget != null && index == standsOn) {
      // A pop and a push in one turn are a replace for the browser.
      _stepBackTarget = null;
      _ownMoveUrl = null;
    }
    if (index != standsOn && index != standsOn + 1) return newState;
    final replaces = index == standsOn;
    // The router writes a new entry if any change of the frame asked for a
    // navigation; a replace can't be made of it, so this one stays as it is.
    if (replaces && _doesFrameNavigate) return newState;
    // The router writes a replace if any change of the frame did; a new entry
    // then goes in now, and the router's write repeats it in place.
    return newState.copyWith(shouldReplace: replaces || _doesFrameReplace);
  }

  // The entry under this frame's unwritten entry, when [newState] shows that
  // entry's page again and the page of the unwritten entry has left without
  // being shown, as a page replaced and popped in one turn. A page never shown
  // needs no entry, so the change goes back to the entry under. Null
  // otherwise.
  int? _entryUnderUnshownPage(UrlState newState) {
    final pending = _pendingIndex;
    if (pending == null || pending != _appIndex || pending == 0) return null;
    final leftPage = _entries[pending]?.topMatch?.id;
    final pageId = newState.topMatch?.id;
    if (leftPage == null ||
        pageId == null ||
        controllerOfPage(leftPage) != null ||
        _entries[pending - 1]?.topMatch?.id != pageId) {
      return null;
    }
    return pending - 1;
  }

  // Goes back to the browser's entry [target] for [newState], stepping the
  // browser back to it when it stands after it, and returns the state to
  // report: a replace of that entry, which repeats what it holds.
  UrlState _stepBackTo(int target, UrlState newState) {
    _pendingIndex = null;
    final standsOn = _frameBrowserIndex;
    if (standsOn != null && standsOn > target) {
      _ownMoveUrl = newState.url;
      _scheduleStepBack(target);
    }
    _frameBrowserIndex = target;
    return newState.copyWith(shouldReplace: true);
  }

  // Records [newState] as the app's entry at [index]; an entry after it is
  // gone, as the browser drops those after a new one.
  void _recordEntry(UrlState newState, int index) {
    _entries.removeWhere((key, _) => key >= index);
    _entries[index] = newState;
    _appIndex = index;
    final standsOn = _frameBrowserIndex;
    if (standsOn != null && index == standsOn + 1 && _doesFrameReplace) {
      // The router writes this frame's url as a replace: the new entry goes
      // in now, and that write repeats it in place.
      _pendingIndex = null;
      _writeEntryNow(index);
    } else if (standsOn != null) {
      _pendingIndex = index;
    }
  }

  // Notes the kind of write that reporting [reported] asks the router for:
  // AutoRouterDelegate reports a replace as neglected and a page pushed over
  // one with the same url as a navigation.
  void _noteReport(UrlState reported, {required bool isPushedOverSameUrl}) {
    if (!_startFrame()) return;
    if (reported.shouldReplace) {
      _doesFrameReplace = true;
    } else if (isPushedOverSameUrl) {
      _doesFrameNavigate = true;
    }
  }

  // Starts this frame's account of the browser, unless it has started, and
  // returns whether there is one. Only the Router writes the url, so before
  // a Router shows this history there is no frame to account for, as when an
  // app navigates before runApp, and maybe no binding to tell the frame's end.
  bool _startFrame() {
    if (_frameBrowserIndex != null) return true;
    if (!isShownByRouter) return false;
    // The browser stands on the app's entry once the router has written the
    // frames before, though the browser may not show it yet; a pop's step
    // back still to be made leaves it where it is until then.
    _frameBrowserIndex = _stepBackTarget != null
        ? _currentIndex
        : (_appIndex ?? _currentIndex);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameBrowserIndex = null;
      _pendingIndex = null;
      _doesFrameReplace = false;
      _doesFrameNavigate = false;
    });
    return true;
  }

  // Writes the entry recorded at [index] to the browser now, over the entry it
  // stands on or as the next one, through the Router's own parser and
  // provider, so neglectWhen still applies. Only while a stack still holds its
  // page, as the first of two pushes stays under the second: a page that left
  // before it showed, such as a guarded page that redirected at once, gets no
  // entry. Does nothing before the router is built.
  void _writeEntryNow(int index) {
    final entry = _entries[index];
    final standsOn = _frameBrowserIndex;
    final pageId = entry?.topMatch?.id;
    final context = router.navigatorKey.currentContext;
    if (entry == null ||
        standsOn == null ||
        (index != standsOn && index != standsOn + 1) ||
        context == null ||
        pageId == null ||
        controllerOfPage(pageId) == null) {
      return;
    }
    final shownBy = Router.maybeOf<Object?>(context);
    // The entry's own replace mark would make the provider replace.
    final information = shownBy?.routeInformationParser
        ?.restoreRouteInformation(
          entry.copyWith(shouldReplace: index == standsOn),
        );
    if (information == null) return;
    shownBy!.routeInformationProvider?.routerReportsNewRouteInformation(
      information,
      type: index == standsOn ? .neglect : .navigate,
    );
    _frameBrowserIndex = index;
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
    final index = isPop && _stepBackTarget != null
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
        _scheduleStepBack(target);
      } else {
        _history.back();
        // A navigation later in this frame starts from the entry the browser
        // is stepping back to.
        if (_startFrame()) _frameBrowserIndex = target;
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
  // pop of the same turn moves the target on; a push of the same turn that
  // takes the browser's entry needs no step (see [_placeEntry]).
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
    final reported = _placeEntry(newState, index);
    onNewUrlState(reported);
    // The url stays the same, so onNewUrlState records no entry for it.
    _recordEntry(reported, index);
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
