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
///   When the page that holds a shared entry leaves from under the entry of
///   another page, the nearest page that shared it and has a browser entry
///   takes it over, so the pages left still have a way back.
class HistoryEntryList {
  /// Creates an empty list that asks [isPageOpen] whether a stack still holds
  /// the page with a given id, and [keepsOut] whether the app keeps the url
  /// of an entry out of the address bar, so that it gets no browser entry.
  new({required this.isPageOpen, this.keepsOut = _keepsNone});

  /// Whether a stack of the app still holds the page with the given id.
  final bool Function(LocalKey pageId) isPageOpen;

  /// Whether the app keeps the url of an entry out of the address bar, as
  /// with neglectWhen: the browser then holds no entry for it.
  final bool Function(UrlState entry) keepsOut;

  static bool _keepsNone(UrlState _) => false;

  final _entries = <UrlState>[];

  // The pages that share the entry of a page over them, as the pages a link
  // opened under its page, each with the page whose entry it shares.
  final _sharing = <LocalKey, LocalKey>{};

  // The pages whose entry a link made.
  final _linkPages = <LocalKey>{};

  // Open pages whose own entries are ahead of the one the browser stands
  // on, as the pages of an app reloaded on a later entry once the user goes
  // back to an entry from before the reload: they share no entry under it.
  final _withEntriesAhead = <LocalKey>{};

  /// The entries, the app's first one first.
  List<UrlState> get entries => .unmodifiable(_entries);

  /// Puts the entries back as [snapshot], a copy of [entries] taken before,
  /// when the app took back the change that made the ones since.
  void restore(List<UrlState> snapshot) {
    _entries
      ..clear()
      ..addAll(snapshot);
  }

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
    // Entries kept while their pages leave are handed over once dropped,
    // see [didDropClosed].
    if (!keepsClosedUnder) _handOverEntries([...under, state]);
    final shown = _showOnTop(state, keepsClosedUnder: keepsClosedUnder);
    final topId = shown.topMatch?.id;
    _sharing.removeWhere((pageId, _) => !isPageOpen(pageId));
    _withEntriesAhead.removeWhere(
      (pageId) => pageId == topId || !isPageOpen(pageId),
    );
    // The page shown may be on its way in, not open yet, as while a guard
    // of its nested router decides: its entry is still a link's.
    _linkPages.removeWhere((pageId) => pageId != topId && !isPageOpen(pageId));
    if (topId != null) {
      _sharing.remove(topId);
      if (isLink) _linkPages.add(topId);
    }
    _repointSharers([...under, shown]);
    _giveEntries([...under, shown], isLink: isLink);
    return shown;
  }

  // Points each page of [wayBack] that shared the entry of a page that has
  // left, its entry with it, to the nearest page over it that has an entry:
  // the page that took the entry's place, as the page that comes on top
  // after a pop or the one that replaced it. That page now holds the link's
  // entry, so a later hand-over finds the pages that share it.
  void _repointSharers(List<UrlState> wayBack) {
    bool hasEntry(LocalKey? pageId) =>
        _entries.any((entry) => entry.topMatch?.id == pageId);
    for (final (place, page) in wayBack.indexed) {
      final pageId = page.topMatch?.id;
      final holderId = _sharing[pageId];
      if (pageId == null ||
          holderId == null ||
          isPageOpen(holderId) ||
          hasEntry(holderId)) {
        continue;
      }
      final heirId = wayBack
          .skip(place + 1)
          .firstWhereOrNull((over) => hasEntry(over.topMatch?.id))
          ?.topMatch
          ?.id;
      if (heirId == null) continue;
      _sharing[pageId] = heirId;
      _linkPages.add(heirId);
    }
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
          _sharing.containsKey(pageId) ||
          _withEntriesAhead.contains(pageId) ||
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
        _sharing[pageId] = overId;
        continue;
      }
      // Right before the latest entries of the page over it: it went in
      // with that page, so after any change of tabs made before, which a
      // place after the entry of the page under it would put it before.
      // The page over it may hold several entries in a row, as states
      // pushed with pushPathState; they stay together.
      var at = _entries.lastIndexWhere((entry) => entry.topMatch?.id == overId);
      while (at > 0 &&
          _entries.elementAtOrNull(at - 1)?.topMatch?.id == overId) {
        at--;
      }
      _entries.insert(at, _withoutReplaceMark(page));
    }
  }

  // Hands the entry of each page that has left, with another entry over it,
  // to the nearest page of [wayBack], the open pages first page first, that
  // shared it and is not kept out of the address bar: that page takes the
  // entry's place with its own url, and the others that shared it share it
  // with that page. Without it they would
  // have no entry once it is dropped, and the back button would skip them.
  // Returns whether one was handed over.
  //
  // The entry of a page on top is not handed over: the page that comes on
  // top in its place takes that place, as before.
  bool _handOverEntries(List<UrlState> wayBack) {
    var didHandOver = false;
    final underTop = _entries.indexed
        .where((placed) => placed.$1 < _entries.length - 1)
        .toList();
    for (final (place, entry) in underTop) {
      final holderId = entry.topMatch?.id;
      if (holderId == null || _isPageOpen(entry)) continue;
      // A page kept out of the address bar would take the entry nowhere.
      final sharers = wayBack.where(
        (page) => _sharing[page.topMatch?.id] == holderId,
      );
      final heir =
          sharers.lastWhereOrNull((page) => !keepsOut(page)) ??
          sharers.lastOrNull;
      final heirId = heir?.topMatch?.id;
      if (heir == null || heirId == null) continue;
      _entries[place] = _withoutReplaceMark(heir);
      _sharing
        ..remove(heirId)
        ..updateAll((_, sharedId) => sharedId == holderId ? heirId : sharedId);
      _linkPages.add(heirId);
      didHandOver = true;
    }
    return didHandOver;
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

    if (last != null && isEntryOf(last, state)) {
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
  /// the entries changed.
  ///
  /// [wayBack] holds the url state of each open page the back button
  /// reaches, the first page first, the page on top last. An entry that
  /// pages of it shared, as the pages a link opened under its page, goes to
  /// the nearest of them instead of being dropped, see [show].
  bool didDropClosed({List<UrlState> wayBack = const []}) {
    final didHandOver = _handOverEntries(wayBack);
    final lengthBefore = _entries.length;
    _entries.removeWhere((entry) => !_isPageOpen(entry));
    return didHandOver || _entries.length < lengthBefore;
  }

  /// Adds [state] as a new entry whatever the entry before it holds, as
  /// history.pushState does.
  void add(UrlState state) {
    _entries.add(_withoutReplaceMark(state));
  }

  /// Replaces the entries with [browserEntries], the browser's own up to the entry
  /// it moved to, as after its back button.
  ///
  /// [withEntriesAhead] holds the ids of open pages whose own entries are
  /// ahead of that entry, as the pages open when the browser moves to an
  /// entry from before the app started. A page shown over them later does
  /// not give them a share in its entry: they keep theirs.
  void reset(
    Iterable<UrlState> browserEntries, {
    Iterable<LocalKey> withEntriesAhead = const [],
  }) {
    _entries
      ..clear()
      ..addAll(browserEntries);
    _sharing.removeWhere((pageId, _) => withEntriesAhead.contains(pageId));
    _withEntriesAhead.addAll(withEntriesAhead);
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

  /// Whether [entry] is the entry of the page on top of [state], with the
  /// url [state] has.
  static bool isEntryOf(UrlState entry, UrlState state) =>
      entry.topMatch?.id == state.topMatch?.id &&
      isSameHistoryUrl(entry.url, state.url);

  static UrlState _withoutReplaceMark(UrlState state) =>
      state.shouldReplace ? _withPathState(state, state.pathState) : state;

  // copyWith can't set a null path state.
  static UrlState _withPathState(UrlState state, Object? pathState) =>
      .new(state.uri, state.segments, pathState: pathState);
}
