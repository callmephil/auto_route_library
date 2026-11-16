import 'package:auto_route/src/router/parser/default_route_parser.dart';
import 'package:auto_route/src/utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show LocalKey;

/// Whether [a] and [b] name the same url, however each is escaped; the empty
/// url is '/'.
bool isSameHistoryUrl(String a, String b) {
  // Decoding throws on a letter outside ASCII, which a decoded url can hold,
  // so parsing first encodes it again. Escaped bytes that aren't valid UTF-8
  // read as U+FFFD, as the matcher reads them.
  String normalize(String url) =>
      url.isEmpty ? '/' : decodeUrlComponent(Uri.parse(url).toString());
  return normalize(a) == normalize(b);
}

/// The entries the browser's history should hold for the pages the app has
/// open, from the app's first entry to the one of the page on top: the path
/// the browser's back button walks.
///
/// It is kept in the app's own time, with no look at the browser, a frame or
/// a turn: the same changes give the same entries however fast they follow
/// each other. Bringing the browser to these entries is the writer's work.
///
/// Each entry is the url state the app showed, and stands for the page that
/// was on top then, [UrlState.topMatch]. The rules, which hold to Flutter's
/// Navigator, where back closes the page on top and a closed page never comes
/// back:
///
/// * An entry whose page has left every stack is dropped, however the page
///   left, popped, replaced or removed, and wherever the entry is, on top or
///   under the entries of other pages. So back never leads to a closed page.
///   Only a page popped from under the page on top keeps its entry until
///   the call that pops them is over, see [show].
/// * A state the page on top already has an entry for, with the same url,
///   is that entry.
/// * A state reported as a replace takes the place of the entry before it,
///   unless that entry was just dropped with its page: the place is then
///   free, and the state is a new entry there.
/// * Any other state is a new entry: another page on top, or another url of
///   the same page.
/// * Every open page under the page on top that the back button should
///   reach has an entry too, see [show]: pages the app opened together get
///   one each, and pages a link opened together share the link's entry.
class HistoryEntryList {
  /// Creates an empty list that asks [isPageOpen] whether a stack still holds
  /// the page with a given id.
  new({required this.isPageOpen});

  /// Whether a stack of the app still holds the page with the given id.
  final bool Function(LocalKey pageId) isPageOpen;

  final _entries = <UrlState>[];

  // The pages that share the entry of a page over them, as the pages a link
  // opened under its page.
  final _sharing = <LocalKey>{};

  // The pages whose entry a link made.
  final _linkPages = <LocalKey>{};

  /// The entries, the app's first one first.
  List<UrlState> get entries => .unmodifiable(_entries);

  /// The app now shows [state], and returns the entry that holds it.
  ///
  /// The returned entry is [state], or the entry the page on top already had
  /// for this url, with the path state that entry holds: the app takes it
  /// over, as it does when the browser's back button returns to that entry.
  ///
  /// With [keepsClosedUnder] an entry whose page has left keeps its place
  /// while the entry of an open page is over it, until [didDropClosed].
  ///
  /// [under] holds the url state of each open page the back button should
  /// reach from [state], the first page first. One that no entry stands for
  /// yet gets an entry of its own, in its place among the others, as each
  /// route of Navigator.pushAll-like calls is closed by a back of its own.
  /// With [isLink], when a link, the launch url or the browser's own move
  /// opened [state], it gets none and shares the entry of [state]: the user
  /// made one navigation, and back leaves it as one. So does a page that
  /// turns up later under an entry a link made, as the first pages of a
  /// nested router that is built a frame after its page.
  UrlState show(
    UrlState state, {
    bool keepsClosedUnder = false,
    List<UrlState> under = const [],
    bool isLink = false,
  }) {
    final shown = _showOnTop(state, keepsClosedUnder: keepsClosedUnder);
    _sharing.removeWhere((pageId) => !isPageOpen(pageId));
    _linkPages.removeWhere((pageId) => !isPageOpen(pageId));
    final topId = shown.topMatch?.id;
    if (topId != null) {
      _sharing.remove(topId);
      if (isLink) _linkPages.add(topId);
    }
    _giveEntries([...under, shown], isLink: isLink);
    return shown;
  }

  // Gives each page of [wayBack] but the last, which has its entry, an
  // entry of its own or a share in the entry over it.
  void _giveEntries(List<UrlState> wayBack, {required bool isLink}) {
    bool hasEntry(UrlState page) =>
        _entries.any((entry) => entry.topMatch?.id == page.topMatch?.id);
    for (final (place, page) in wayBack.indexed) {
      final pageId = page.topMatch?.id;
      if (pageId == null ||
          place == wayBack.length - 1 ||
          _sharing.contains(pageId) ||
          hasEntry(page)) {
        continue;
      }
      // The last page has its entry, so one over is always found.
      final overId = wayBack
          .skip(place + 1)
          .firstWhereOrNull(hasEntry)
          ?.topMatch
          ?.id;
      if (overId == null) continue;
      if (isLink || _linkPages.contains(overId)) {
        _sharing.add(pageId);
        continue;
      }
      // After the entry of the nearest page under it that has one, else
      // before the entry of the page over it.
      final belowId = wayBack
          .take(place)
          .toList()
          .reversed
          .firstWhereOrNull(hasEntry)
          ?.topMatch
          ?.id;
      final at = belowId == null
          ? _entries.indexWhere((entry) => entry.topMatch?.id == overId)
          : _entries.lastIndexWhere((entry) => entry.topMatch?.id == belowId) +
                1;
      _entries.insert(at, _withoutReplaceMark(page));
    }
  }

  UrlState _showOnTop(UrlState state, {required bool keepsClosedUnder}) {
    final topBefore = _entries.lastOrNull;
    // The place on top is free when the entry that held it leaves with its
    // page.
    final didDrop = topBefore != null && !_isPageOpen(topBefore);
    if (keepsClosedUnder) {
      _dropClosedOnTop();
    } else {
      _entries.removeWhere((entry) => !_isPageOpen(entry));
    }
    final last = didDrop ? _entries.lastOrNull : topBefore;
    final entry = _withoutReplaceMark(state);

    if (last != null && _isEntryOf(last, state)) {
      // The path state is the entry's own: a navigation never carries one.
      final shown = state.pathState == null
          ? _withPathState(entry, last.pathState)
          : entry;
      _replaceTop(shown);
      return shown;
    }
    if (state.shouldReplace && !didDrop && last != null) {
      _replaceTop(entry);
    } else {
      _entries.add(entry);
    }
    return entry;
  }

  /// Drops every entry whose page has left a stack, and returns whether
  /// there was one.
  bool didDropClosed() {
    final lengthBefore = _entries.length;
    _entries.removeWhere((entry) => !_isPageOpen(entry));
    return _entries.length < lengthBefore;
  }

  /// Adds [state] as a new entry whatever the entry before it holds, as
  /// history.pushState does.
  void add(UrlState state) {
    _entries.add(_withoutReplaceMark(state));
  }

  /// Replaces the entries with [browserEntries], the browser's own up to the entry
  /// it moved to, as after its back button.
  void reset(Iterable<UrlState> browserEntries) {
    _entries
      ..clear()
      ..addAll(browserEntries);
  }

  void _dropClosedOnTop() {
    for (
      var last = _entries.lastOrNull;
      last != null && !_isPageOpen(last);
      last = _entries.lastOrNull
    ) {
      _entries.removeLast();
    }
  }

  void _replaceTop(UrlState entry) {
    _entries
      ..removeLast()
      ..add(entry);
  }

  // Whether a stack still holds the page [entry] stands for; an entry that
  // holds no page, as the empty url of an app that shows none, stands for
  // none.
  bool _isPageOpen(UrlState entry) {
    final pageId = entry.topMatch?.id;
    return pageId != null && isPageOpen(pageId);
  }

  // Whether [entry] is the entry of the page on top of [state], with the url
  // [state] has.
  static bool _isEntryOf(UrlState entry, UrlState state) =>
      entry.topMatch?.id == state.topMatch?.id &&
      isSameHistoryUrl(entry.url, state.url);

  static UrlState _withoutReplaceMark(UrlState state) =>
      state.shouldReplace ? _withPathState(state, state.pathState) : state;

  // copyWith can't set a null path state.
  static UrlState _withPathState(UrlState state, Object? pathState) =>
      .new(state.uri, state.segments, pathState: pathState);
}
