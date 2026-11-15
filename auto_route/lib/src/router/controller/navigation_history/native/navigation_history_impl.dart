import 'dart:async';

import 'package:auto_route/auto_route.dart'
    show RouteMatch, StackRouter, UrlState;
import 'package:auto_route/src/router/controller/navigation_history/navigation_history.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// An implementation of [NavigationHistory]
/// That's used for native platforms
class NavigationHistoryImpl extends NavigationHistory {
  /// Default constructor;
  new(this.router);

  @override
  final StackRouter router;

  final _entries = <_HistoryEntry>[];
  bool _isNavigatingBack = false;
  // The url back() navigates to, until the router reports it.
  String? _backTargetUrl;
  int _backCount = 0;
  bool _isRebuildingAfterPop = false;

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
    if (_isLastEntry(newState)) return;

    // Don't add entries during back navigation to prevent duplicates
    if (_isNavigatingBack) return;

    if (_isRebuildingAfterPop) {
      // The last entry belongs to the popped page; drop it so back() can't
      // return to it. If the page now on top is the entry before, _addEntry
      // skips it as the same page.
      if (_entries.isNotEmpty) _entries.removeLast();
      _addEntry(newState.copyWith(shouldReplace: false));
      return;
    }

    _addEntry(newState);
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
    final route = UrlState.toHierarchy(urlState.segments);
    final newEntry = _HistoryEntry(route, urlState.url, urlState.topMatch!.id);

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

    // limit history registration to 20 entries
    if (_entries.length > 20) {
      _entries.removeAt(0);
    }
    if (urlState.shouldReplace && length > 0) {
      _entries.removeLast();
      // The entry before may already hold this url, e.g. the page a redirect
      // was shown for.
      if (_entries.lastOrNull?.url == urlState.url) return;
    }
    _entries.add(newEntry);
  }

  @override
  void back() {
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
