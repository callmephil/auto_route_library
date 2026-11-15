import 'package:auto_route/src/router/parser/default_route_parser.dart';
import 'package:auto_route/src/utils.dart';
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
/// * A state the page on top already has an entry for, with the same url,
///   is that entry.
/// * A state reported as a replace takes the place of the entry before it,
///   unless that entry was just dropped with its page: the place is then
///   free, and the state is a new entry there.
/// * Any other state is a new entry: another page on top, or another url of
///   the same page.
class HistoryEntryList {
  /// Creates an empty list that asks [isPageOpen] whether a stack still holds
  /// the page with a given id.
  new({required this.isPageOpen});

  /// Whether a stack of the app still holds the page with the given id.
  final bool Function(LocalKey pageId) isPageOpen;

  final _entries = <UrlState>[];

  /// The entries, the app's first one first.
  List<UrlState> get entries => .unmodifiable(_entries);

  /// The app now shows [state], and returns the entry that holds it.
  ///
  /// The returned entry is [state], or the entry the page on top already had
  /// for this url, with the path state that entry holds: the app takes it
  /// over, as it does when the browser's back button returns to that entry.
  UrlState show(UrlState state) {
    final topBefore = _entries.lastOrNull;
    // The place on top is free when the entry that held it leaves with its
    // page.
    final didDrop = topBefore != null && !_isPageOpen(topBefore);
    _entries.removeWhere((entry) => !_isPageOpen(entry));
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
