// Native browser session history, as the random sequence test expects it.
// Native behavior this holds to: the HTML Living Standard, session history
// (§7.2, §7.4): pushState removes the entries ahead, replaceState changes
// the current entry, back, forward and go(n) keep every entry, no call
// removes an entry that is not current, and a landing hands the entry's
// saved state back. Flutter's Navigator: pop and popUntil close the pages on
// top, and a page that was popped, replaced or removed never comes back.
// So each entry keeps the stack it shows; the way back keeps only entries of
// open pages; to drop one, the browser goes back over it and pushes again.

/// A page: its id is new each time a page opens; its url is what it shows.
typedef ModelPage = ({int id, String url});

/// The stack of pages an entry shows.
typedef ModelEntry = ({List<ModelPage> under, ModelPage top});

class NativeHistoryModel {
  new([String url = '/'])
    : _shownEntry = (under: const [], top: (id: 0, url: url)) {
    _entries.add(_shownEntry);
  }

  final _entries = <ModelEntry>[];
  ModelEntry _shownEntry;
  int _index = 0;
  int _lastId = 0;

  List<String> get urls => [for (final entry in _entries) entry.top.url];

  int get index => _index;

  List<String> get stack => _urlsOf(_shownEntry);

  String get shown => _shownEntry.top.url;

  bool get canPop => _shownEntry.under.isNotEmpty;

  String get held => [
    for (final (number, entry) in _entries.indexed)
      '${number == _index ? '>' : ''}${entry.top.url}',
  ].join(' ');

  void push(String url) =>
      _show((under: [..._shownEntry.under, _shownEntry.top], top: _open(url)));

  /// Changes what the page on top shows, as a tab change does.
  void changeTop(String url) => _show((
    under: _shownEntry.under,
    top: (id: _shownEntry.top.id, url: url),
  ));

  void replace(String url) =>
      _show((under: _shownEntry.under, top: _open(url)));

  void pop() => popTo(_shownEntry.under.length);

  /// Keeps the first [count] pages, as popUntil does.
  void popTo(int count) {
    final kept = [..._shownEntry.under, _shownEntry.top].take(count).toList();
    if (kept case [...final under, final top]) {
      _show((under: under, top: top));
    }
  }

  bool canGo(int delta) {
    final to = _index + delta;
    return delta != 0 && to >= 0 && to < _entries.length;
  }

  /// The urls of the stack of the entry [delta] entries away.
  List<String> stackAt(int delta) {
    final entry = _entries.elementAtOrNull(_index + delta);
    return entry == null ? const [] : _urlsOf(entry);
  }

  /// Whether the entry [delta] entries away shows the open pages where it
  /// shares a place with them, as it does unless a replace changed one.
  bool agreesWith(int delta) {
    final to = _entries.elementAtOrNull(_index + delta);
    if (to == null) return false;
    final toPages = [...to.under, to.top];
    for (final (place, page) in [
      ..._shownEntry.under,
      _shownEntry.top,
    ].indexed) {
      final other = toPages.elementAtOrNull(place);
      if (other != null && other.id != page.id) return false;
    }
    return true;
  }

  void go(int delta) {
    final to = _entries.elementAtOrNull(_index + delta);
    if (delta == 0 || to == null) throw RangeError.value(delta, 'delta');
    _index += delta;
    _shownEntry = to;
  }

  ModelPage _open(String url) => (id: ++_lastId, url: url);

  // The way back of [pages]: entries of open pages, then the page on top.
  void _show(ModelEntry pages) {
    final open = {for (final page in pages.under) page.id, pages.top.id};
    final kept = _entries
        .take(_index + 1)
        .where((entry) => open.contains(entry.top.id))
        .toList();
    final wayBack = [
      ...(kept.lastOrNull?.top == pages.top
          ? kept.take(kept.length - 1)
          : kept),
      pages,
    ];
    var same = 0;
    while (same < wayBack.length &&
        same <= _index &&
        _entries.elementAtOrNull(same)?.top ==
            wayBack.elementAtOrNull(same)?.top) {
      same++;
    }
    _shownEntry = pages;
    if (same == wayBack.length) {
      // history.go(-n): the entries ahead stay.
      _index = same - 1;
      _entries[_index] = pages;
    } else if (same == wayBack.length - 1 && same == _index) {
      // history.replaceState: the entries ahead stay.
      _entries[_index] = pages;
    } else {
      // history.go back to the last entry kept, then pushState for each
      // other one: the entries ahead go.
      _entries
        ..removeRange(same, _entries.length)
        ..addAll(wayBack.skip(same));
      _index = _entries.length - 1;
    }
  }
}

List<String> _urlsOf(ModelEntry entry) => [
  for (final page in entry.under) page.url,
  entry.top.url,
];
