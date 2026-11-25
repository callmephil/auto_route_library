import 'dart:async';
import 'dart:collection';

import 'package:auto_route/src/router/controller/navigation_history/browser/history_entry_list.dart';
import 'package:auto_route/src/router/parser/default_route_parser.dart';

/// What [HistoryWriter] needs from a browser's history: the HTML History API
/// as Flutter's web engine wraps it.
abstract interface class HistoryBrowser {
  /// The number of the entry the browser stands on, counted from the first
  /// entry the app wrote: the engine's serial count.
  int get index;

  /// The url of the entry the browser stands on, as the app reads it.
  String get url;

  /// The state the app saved in the entry the browser stands on, or null.
  Object? get state;

  /// Writes [entry] over the entry the browser stands on when [replaces] is
  /// true, as history.replaceState does, or as a new entry after it, as
  /// history.pushState does, which drops the entries ahead.
  void write(UrlState entry, {required bool replaces});

  /// Completes once every entry written so far is in the browser.
  Future<void> whenWritten();

  /// Asks the browser to step [delta] entries, as history.go does. It
  /// returns at once; the browser lands later, or never when it has no such
  /// entry.
  void go(int delta);

  /// Whether the browser has an entry of the app's own origin ahead of the
  /// one it stands on, as the Navigation API's canGoForward tells; true when
  /// the browser can't tell. An entry of another site ahead counts as none,
  /// since the Navigation API lists only the entries of its own origin.
  bool get canGoForward;

  /// Whether the app keeps the url of [entry] out of the address bar, so
  /// that the browser gets no entry for it.
  bool keepsOut(UrlState entry);

  /// Whether entries can be written now: a Router shows the app, and writes
  /// go through its route information provider.
  bool get canWrite;

  /// Whether the browser keeps the entries written to it.
  ///
  /// False where the app's reports reach no browser history, as in a widget
  /// test that does not connect the engine to the browser. The writer then
  /// tells only the url of the page on top, on each change, and never
  /// steps.
  bool get keepsEntries;

  /// Starts calling [onLanding] each time the browser has landed on an
  /// entry, as its popstate event tells.
  void listen(void Function() onLanding);

  /// Stops calling the listener given to [listen].
  void close();
}

/// Brings a browser's history to the entries the app should have, one
/// operation at a time, as the browser's one writer.
///
/// [bringTo] takes the entries wanted, from the app's first entry to the one
/// of the page on top, and queues them. The writer works through the queue
/// in order. For each it finds the first entry the browser holds otherwise:
///
/// * none, and the browser stands elsewhere: it steps to the last entry
///   wanted, which leaves the entries after it ahead, as history.back does.
///   When the browser stands on an entry of that last entry's page, at its
///   url, the entries between are of closed pages: it writes that page's
///   entry again after the entry before it, which drops them;
/// * the entry the browser stands on: it writes over it, then adds the rest,
///   or steps on to them when the browser holds them;
/// * an entry under it: it steps back to the entry before that one and adds
///   from there, so nothing stale stays on the way back. It writes over the
///   app's first entry, which has none before it, and one [owe] noted.
///
/// It never writes while a step is on its way, since the browser would put
/// the write on the entry it is leaving, and never steps before its writes
/// are in. Entries wanted one after another are never merged, except steps
/// back that follow each other. So where the browser ends depends only on
/// the order the app asked in, not on when the browser lands: several
/// changes at once leave it as the same changes a frame apart do, the
/// entries ahead included.
///
/// A landing the writer did not ask for is the user's, by the back or
/// forward button or the address bar: the writer drops what it still had to
/// do and calls [onUserMove], and the app follows the browser.
class HistoryWriter {
  /// Creates a writer for [_browser], whose current entry is the app's first.
  new(
    this._browser, {
    this.onUserMove,
    this.landingLimit = const Duration(seconds: 1),
  }) : first = _browser.index,
       _index = _browser.index,
       _reachedTop = _browser.index,
       _firstUrl = _browser.url {
    _browser.listen(browserLanded);
  }

  final HistoryBrowser _browser;

  /// Called when the browser moved without the writer asking it to.
  final void Function()? onUserMove;

  /// How long the writer waits for a step to land before it reads where the
  /// browser stands, as after a step the browser had no entry for.
  final Duration landingLimit;

  // What each browser entry holds, by its number, as far as known.
  final _entries = <int, UrlState>{};
  final _owed = <int, UrlState>{};

  final _queue = Queue<_Work>();

  /// The number of the app's first entry: the entry the browser stood on
  /// when the app started. The app sets a lower one when it follows the user
  /// to an entry from before it started, which a reload leaves under the
  /// entry the app starts on.
  int first;

  int _index;

  // The entry of the app's page on top, as the writer last reached it.
  int _reachedTop;

  // The url the browser opened the app at, when the app was first shown.
  String? _firstUrl;

  // The entry a step of the writer's own is on its way to, and what ends the
  // wait for it: true when it landed there.
  int? _stepTarget;
  int _stepDelta = 0;
  Completer<bool>? _landing;
  Timer? _landingTimer;

  // Whether the step on its way was asked for by the app, with [step]: its
  // landing is followed like the user's.
  bool _isAppStep = false;

  // Whether the user's step landed while a step of the writer's own was on
  // its way: the browser takes both, and the app follows where they end.
  bool _isUserStepMixedIn = false;

  // The entries the writer was asked to bring the browser to last.
  _Entries? _lastWanted;

  // The url of the entry a step of the writer's own landed on, until the
  // platform's report of that landing is taken.
  String? _ownLandingUrl;

  // Whether the browser landed on an entry the platform has not reported.
  bool _isLandingUnreported = false;

  /// Whether the route handed over last is the user's landing, not a link.
  bool get isUserLanding => _isUserLanding;
  bool _isUserLanding = false;

  /// How many entries the user's latest landing moved the browser forward.
  int get userStep => _userStep;
  int _userStep = 0;

  // The url the Router's provider holds, written or handed over last.
  String? _providerUrl;

  // What a browser that keeps no entries was told last, see [_tellTop].
  UrlState? _toldTop;

  bool _isRunning = false;
  bool _isWriting = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // Counts the moves the writer did not ask for, so that work under way
  // when one came stops.
  int _userMoves = 0;

  Completer<void>? _idle;

  /// The number of the entry the browser stands on, as far as the writer
  /// knows: it has not heard of a step of the user's that is still on its
  /// way.
  int get index => _index;

  /// Whether the writer has nothing left to do, or can do nothing for now,
  /// see [pause].
  bool get isIdle =>
      !_isRunning && (_queue.isEmpty || _isPaused || _writeHolds > 0);

  /// Whether [entry], the one at [place] in a list of the app's entries,
  /// has a browser entry.
  ///
  /// Every entry has one but an entry the app keeps out of the address bar,
  /// see [HistoryBrowser.keepsOut]. The app's first entry, though, has the
  /// one the browser made when it opened the app at its url, kept out or
  /// not: that page is on the way back, as it would be without the app.
  bool hasBrowserEntry(int place, UrlState entry) {
    if (!_browser.keepsOut(entry)) return true;
    final firstUrl = _firstUrl;
    return place == 0 &&
        firstUrl != null &&
        isSameHistoryUrl(entry.url, firstUrl);
  }

  /// What the browser entry with the number [number] holds, or null when the
  /// writer never wrote it, as an entry from before a reload.
  UrlState? entryAt(int number) => _entries[number];

  /// Completes once the writer has nothing left to do, or can do nothing
  /// for now.
  Future<void> whenIdle() {
    if (isIdle) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Holds the work back until [release], for a change the app may take back
  /// before it is written. Calls nest.
  void hold() {
    if (_writeHolds++ == 0) {
      _queuedAtHold = _queue.length;
      _wantedAtHold = _lastWanted;
    }
  }

  /// Ends one [hold]. Once none is left, the entries wanted meanwhile are
  /// merged into the last of them, so the browser gets only where the app
  /// ended, and the work goes on. With [dropsChanges] they are dropped
  /// instead: the app took the change back, and the browser holds what it
  /// should.
  void release({bool dropsChanges = false}) {
    if (_writeHolds == 0) return;
    if (dropsChanges) _dropsChangesHeld = true;
    if (--_writeHolds > 0) return;
    final kept = <_Work>[];
    for (final (place, work) in _queue.indexed) {
      if (_dropsChangesHeld && place >= _queuedAtHold) break;
      if (work is _Entries && kept.lastOrNull is _Entries) kept.removeLast();
      kept.add(work);
    }
    if (_dropsChangesHeld) _lastWanted = _wantedAtHold;
    _dropsChangesHeld = false;
    _queue
      ..clear()
      ..addAll(kept);
    if (isIdle) _completeIdle();
    _run();
  }

  // The holds not released yet, see [hold].
  int _writeHolds = 0;
  bool _dropsChangesHeld = false;

  // What the queue held, and what was wanted last, when the first hold began.
  int _queuedAtHold = 0;
  _Entries? _wantedAtHold;

  /// Holds the work back until [resume], as while no Router shows the app
  /// and nothing can be written.
  void pause() => _isPaused = true;

  /// Takes up the work again after [pause].
  ///
  /// A writer that has written nothing yet starts from the entry the
  /// browser stands on now: the app may be shown long after its router was
  /// made, and the browser may have moved meanwhile.
  void resume() {
    if (_isPaused && _entries.isEmpty) {
      _index = _browser.index;
      first = _index;
      _firstUrl = _browser.url;
    }
    _isPaused = false;
    _run();
  }

  /// Forgets what the browser holds and what was still to do, and holds
  /// the work back until [resume]: another writer writes the browser now.
  /// The writer then starts from the entry the browser stands on, and
  /// writes it first.
  void restart() {
    _userMoves++;
    _queue.clear();
    _endStep(didLand: false);
    _entries.clear();
    _owed.clear();
    _toldTop = null;
    _ownLandingUrl = null;
    _isLandingUnreported = false;
    _isPaused = true;
    if (isIdle) _completeIdle();
  }

  /// Stops the writer for good.
  void dispose() {
    _isDisposed = true;
    _browser.close();
    _queue.clear();
    _endStep(didLand: false);
    _completeIdle();
  }

  /// Queues [entries], the app's first entry first, as what the browser
  /// should hold up to the entry it stands on. An entry the app keeps out of
  /// the address bar, see [HistoryBrowser.keepsOut], is left out when its
  /// turn comes.
  ///
  /// [isReplace] tells that the app reported the last entry as a replace.
  /// Only a browser that keeps no entries needs it, see
  /// [HistoryBrowser.keepsEntries]: the others are brought to the entries
  /// whatever the app reported.
  void bringTo(List<UrlState> entries, {bool isReplace = false}) {
    if (entries.isEmpty || _isDisposed) return;
    final wanted = _Entries(List.unmodifiable(entries), isReplace: isReplace);
    _lastWanted = wanted;
    _queue.add(wanted);
    _run();
  }

  /// Queues a step of [delta] entries that the app asked for, behind what is
  /// still to do. The app follows where it lands, as it follows the user's
  /// back and forward buttons.
  void step(int delta) {
    if (delta == 0 || _isDisposed) return;
    _queue.add(_Step(delta));
    _run();
  }

  /// Tells the writer that the browser has landed on an entry, as its
  /// popstate event does.
  void browserLanded() {
    if (_isDisposed) return;
    final landedAt = _browser.index;
    // Known already: the platform's report of this landing came first.
    if (landedAt == _index) return;
    _isLandingUnreported = true;
    if (_didOwnStepLand(landedAt)) _ownLandingUrl = _browser.url;
  }

  /// Whether [reported], a route the Router just handed to the app, gives
  /// the app nothing to follow.
  ///
  /// That is so when it only tells of a step the writer made itself, and
  /// when, with no landing since the last report and the writer still at
  /// work, [reported] is the url the Router's provider held already: the
  /// Router then parsed again what its provider holds, as it does when a
  /// dependency of its own changes, and that is what the writer wrote
  /// before, which the app has left behind. Any other route with no
  /// landing is a link, as the platform or a test hands one over.
  ///
  /// The report of a landing and [browserLanded] come in either order, and
  /// the Router drops a report when a newer one comes while it is parsed, so
  /// each is taken on its own: a step counts as landed by whichever comes
  /// first.
  bool hasNothingToFollow(UrlState reported) {
    final heldByProvider = _providerUrl;
    _providerUrl = reported.url;
    _isUserLanding = false;
    // A writer that can't write has written nothing the Router could hand
    // over again.
    if (_isDisposed || _isPaused) return false;
    final landedAt = _browser.index;
    // While the writer writes, the browser's number is behind the writer's
    // own account, and only the browser's event tells of a move.
    if (!_isWriting && landedAt != _index) {
      // The report came before the browser's event.
      _isLandingUnreported = false;
      _ownLandingUrl = null;
      final isOwn = _didOwnStepLand(landedAt);
      _isUserLanding = !isOwn;
      return isOwn;
    }
    if (!_isLandingUnreported) {
      // No landing. The url the provider held already, while the writer
      // has work to do, is the one it wrote before, which the app has left
      // behind. Once the writer has none, that url is the one the app
      // shows; and another url is a link.
      return (_isRunning || _queue.isNotEmpty) &&
          heldByProvider != null &&
          isSameHistoryUrl(heldByProvider, reported.url);
    }
    _isLandingUnreported = false;
    final ownLandingUrl = _ownLandingUrl;
    _ownLandingUrl = null;
    _isUserLanding =
        ownLandingUrl == null || !isSameHistoryUrl(ownLandingUrl, reported.url);
    return !_isUserLanding;
  }

  // The browser landed on the entry [landedAt], which it did not stand on
  // before. Returns whether the app has nothing to follow there: the step
  // the writer asked for, for itself, landed, or the user's step landed
  // first and the writer's is still to come. Any other landing is followed
  // by the app.
  bool _didOwnStepLand(int landedAt) {
    final isStep = landedAt == _stepTarget;
    if (isStep && !_isAppStep && !_isUserStepMixedIn) {
      _index = landedAt;
      _endStep(didLand: true);
      return true;
    }
    if (isStep) {
      _endStep(didLand: false);
    } else if (_stepTarget != null) {
      // A step of the user's landed first. The browser counts the writer's
      // step, still on its way, from there.
      final target = _stepTarget = landedAt + _stepDelta;
      // When that step stays among the app's entries, the app follows where
      // the two end, once the writer's lands, and never the entry between
      // them, which the app may have left already. A step under the app's
      // first entry would leave the app, or is lost.
      if (!_isAppStep && target >= first) {
        _index = landedAt;
        _isUserStepMixedIn = true;
        return true;
      }
    }
    _followUser();
    return false;
  }

  /// Notes that the browser entry [number] now holds [entry].
  void adopt(int number, UrlState entry) {
    _entries[number] = entry;
    _owed.remove(number);
    _reachedTop = number;
  }

  /// Notes that the app shows [entry] for the entry [number], which the
  /// browser stands beyond: it is written once the browser stands there.
  void owe(int number, UrlState entry) {
    if (number < _index && !_isSame(_entries[number], entry)) {
      _owed[number] = entry;
    } else {
      _owed.remove(number);
    }
  }

  /// Whether the entry [number] is owed [entry], see [owe].
  bool owes(int number, UrlState? entry) => _isSame(_owed[number], entry);

  // The browser moved without the writer asking: the user did, or the app
  // through [step]. The work left no longer fits, and the app follows; a
  // step of the writer's on its way holds the work until it lands too.
  void _followUser() {
    _userMoves++;
    _ownLandingUrl = null;
    _queue.clear();
    _userStep = _browser.index - _index;
    _index = _browser.index;
    final held = _entries[_index];
    if (held != null && !isSameHistoryUrl(held.url, _browser.url)) {
      // A new entry, as for a typed url, which dropped the ones after it.
      _forgetFrom(_index);
    }
    onUserMove?.call();
  }

  void _run() {
    if (_isRunning || _isPaused || _isDisposed || _writeHolds > 0) return;
    _isRunning = true;
    unawaited(_work());
  }

  Future<void> _work() async {
    try {
      // After the turn, so the changes made in it are all in the queue.
      await Future<void>.value();
      while (_queue.isNotEmpty &&
          !_isPaused &&
          !_isDisposed &&
          _writeHolds == 0) {
        switch (_nextWork()) {
          case _Entries(:final entries, :final isReplace):
            final wanted = _withBrowserEntries(entries);
            if (_browser.keepsEntries) {
              await _reach(wanted);
            } else {
              _tellTop(wanted, isReplace: isReplace);
            }
          case _Step(:final delta) when _browser.keepsEntries:
            if (delta < 0 || _browser.canGoForward) {
              await _stepFor(app: true, delta);
            } else {
              // No entry of the app's own origin ahead, the only ones the
              // browser lists. Another site's entry may still be there, so
              // the step is asked as history.forward() asks it: the browser
              // goes to that site or, with nothing ahead, does nothing.
              // Either way no landing reaches the app, and waiting for one
              // would hold the work behind it.
              _browser.go(delta);
            }
          case _Step():
          // With no entries kept there is none to step to.
        }
      }
    } finally {
      _isRunning = false;
      if (isIdle) _completeIdle();
    }
  }

  void _completeIdle() {
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }

  // The next work in the queue. Steps back that follow each other become
  // one: entries the browser holds already, then fewer of them.
  _Work _nextWork() {
    var work = _queue.removeFirst();
    for (
      var next = _queue.firstOrNull;
      work is _Entries &&
          next is _Entries &&
          _isStepBackFrom(next.entries, work.entries);
      next = _queue.firstOrNull
    ) {
      work = _queue.removeFirst();
    }
    return work;
  }

  // Whether the browser holds [entries] already and [fewer] is the first of
  // them: reaching one after the other is two steps back, or one.
  bool _isStepBackFrom(List<UrlState> fewer, List<UrlState> entries) {
    if (fewer.length >= entries.length || _firstUnheld(entries) != null) {
      return false;
    }
    for (final (offset, entry) in fewer.indexed) {
      final other = entries.elementAtOrNull(offset);
      if (other == null ||
          !isSameHistoryUrl(entry.url, other.url) ||
          entry.pathState != other.pathState) {
        return false;
      }
    }
    return true;
  }

  // Tells the url of the page on top of [entries] to a browser that keeps
  // no entries, as Flutter's Router reports a change: nothing when the url
  // and its state are the ones told last, over the last one for the first
  // url and for a change reported as a replace ([isReplace]), and as a new
  // entry otherwise, a pop included. That is what a test that listens to
  // the navigation channel hears.
  void _tellTop(List<UrlState> entries, {required bool isReplace}) {
    final top = entries.lastOrNull;
    if (top == null) return;
    final told = _toldTop;
    if (told != null &&
        isSameHistoryUrl(told.url, top.url) &&
        told.pathState == top.pathState) {
      return;
    }
    _toldTop = top;
    _providerUrl = top.url;
    _browser.write(top, replaces: told == null || isReplace);
  }

  // Brings the browser to [entries]; stops when the user moves it meanwhile.
  Future<void> _reach(List<UrlState> entries) async {
    if (entries.isEmpty) return;
    // A move of the user's that no event told of.
    if (_browser.index != _index) {
      _followUser();
      return;
    }
    _owed.removeWhere(
      (number, owed) =>
          number < first ||
          !_isSame(owed, entries.elementAtOrNull(number - first)),
    );
    final userMoves = _userMoves;
    var unheld = _firstUnheld(entries) ?? _repeatedTopPlace(entries);
    // On the entry the browser stands on, with the entries after it held, as
    // after a back the page on top refused: it writes that one, then steps on.
    if (unheld != null &&
        first + unheld == _index &&
        unheld < entries.length - 1 &&
        _firstUnheld(entries, start: unheld + 1) == null) {
      _adoptAll(entries, unheld);
      await _writeAll(entries.skip(unheld).take(1), replaces: true);
      if (userMoves != _userMoves) return;
      unheld = null;
    }
    if (unheld == null) {
      final top = first + entries.length - 1;
      if (_index != top) await _stepFor(top - _index);
      if (userMoves == _userMoves) {
        _adoptAll(entries, entries.length);
        _reachedTop = _index;
      }
      return;
    }
    final at = first + unheld;
    // Written over where it is the entry the browser stands on, one owed to
    // it, or the app's first, which has nothing before it to step back to.
    final replaces =
        at == _index || _owed.containsKey(at) || (at < _index && unheld == 0);
    final from = replaces ? at : at - 1;
    if (from != _index && !await _stepFor(from - _index)) return;
    if (userMoves != _userMoves) return;
    _adoptAll(entries, unheld);
    await _writeAll(entries.skip(unheld), replaces: replaces);
    // Writes that never reached the browser, as through a route information
    // provider that writes no entry: the writer knows only where it stands.
    if (userMoves == _userMoves &&
        !_isLandingUnreported &&
        _browser.index != _index) {
      _index = _browser.index;
      _forgetFrom(_index + 1);
    }
    if (userMoves == _userMoves) _reachedTop = _index;
  }

  Future<void> _writeAll(
    Iterable<UrlState> entries, {
    required bool replaces,
  }) async {
    _isWriting = true;
    try {
      for (final (offset, entry) in entries.indexed) {
        _write(entry, replaces: replaces && offset == 0);
      }
      await _browser.whenWritten();
    } finally {
      _isWriting = false;
    }
  }

  // The place of the last of [entries], which the browser holds all, when
  // the entry the browser stands on is after them and holds the page of
  // that last entry, at its url and with its state. Only entries of pages
  // that closed were between two entries of that page, as the pages the
  // app took off a tab not on screen between two visits of the tab on
  // screen. A step back would show nothing new and leave them ahead for the
  // forward button, so the page's entry is written again after the entry
  // before it, which drops them. Null otherwise.
  int? _repeatedTopPlace(List<UrlState> entries) {
    final standingOn = _entries[_index];
    final top = entries.lastOrNull;
    if (standingOn == null ||
        top == null ||
        _index <= first + entries.length - 1 ||
        !HistoryEntryList.isEntryOf(standingOn, top) ||
        standingOn.pathState != top.pathState) {
      return null;
    }
    return entries.length - 1;
  }

  int? _firstUnheld(List<UrlState> entries, {int start = 0}) {
    for (final (offset, entry) in entries.indexed.skip(start)) {
      final isTop = offset == entries.length - 1;
      if (!_holds(first + offset, entry, isTop: isTop)) return offset;
    }
    return null;
  }

  /// Whether the browser holds or owes each of the app's [entries].
  bool holdsAll(List<UrlState> entries) => _withBrowserEntries(entries).indexed
      .every((placed) => _holds(first + placed.$1, placed.$2, isTop: false));

  List<UrlState> _withBrowserEntries(List<UrlState> entries) => [
    for (final (place, entry) in entries.indexed)
      if (hasBrowserEntry(place, entry)) entry,
  ];

  // Whether the browser entry [number] holds the url and path state of
  // [entry]. Ahead of the browser, past [_reachedTop], none does: the app adds
  // [entry] there, and pushState drops the entries ahead. One never written,
  // as from before a reload, is read only while the browser stands on it.
  // The app's first entry is written once, as Flutter's Router reports it.
  // One owed under the top does, see [owe], but where the browser stands.
  bool _holds(int number, UrlState entry, {required bool isTop}) {
    if (number > _index && number > _reachedTop) return false;
    if (!isTop && number != _index && _isSame(_owed[number], entry)) {
      return true;
    }
    final held = _entries[number];
    if (held != null) return _isSame(held, entry);
    return _entries.isNotEmpty &&
        number == _index &&
        isSameHistoryUrl(_browser.url, entry.url) &&
        _browser.state == entry.pathState;
  }

  static bool _isSame(UrlState? held, UrlState? entry) =>
      held != null &&
      entry != null &&
      isSameHistoryUrl(held.url, entry.url) &&
      held.pathState == entry.pathState;

  // Notes the first [count] of [entries] as what the browser holds: the same
  // urls, for pages that may have been opened anew. An owed one stays.
  void _adoptAll(List<UrlState> entries, int count) {
    for (final (offset, entry) in entries.take(count).indexed) {
      if (!_owed.containsKey(first + offset)) _entries[first + offset] = entry;
    }
  }

  void _forgetFrom(int number) {
    _entries.removeWhere((held, _) => held >= number);
    _owed.removeWhere((owed, _) => owed >= number);
  }

  void _write(UrlState entry, {required bool replaces}) {
    assert(
      _stepTarget == null,
      'Nothing is written while a step is on its way.',
    );
    if (!replaces) {
      _index++;
      _forgetFrom(_index);
    }
    _entries[_index] = entry;
    _owed.remove(_index);
    _providerUrl = entry.url;
    _browser.write(entry, replaces: replaces);
  }

  // Steps the browser [delta] entries and waits for it to land. Returns
  // whether it landed there as a step of the writer's own; a step for the
  // app is followed like the user's wherever it lands.
  Future<bool> _stepFor(int delta, {bool app = false}) {
    final landing = _landing = Completer<bool>();
    _stepTarget = _index + delta;
    _stepDelta = delta;
    _isAppStep = app;
    _landingTimer = Timer(landingLimit, _readWhereBrowserStands);
    _browser.go(delta);
    return landing.future;
  }

  // The step never landed: the browser had no such entry, or the event was
  // lost.
  void _readWhereBrowserStands() {
    final target = _stepTarget;
    if (target == null) return;
    final wasUserStepMixedIn = _isUserStepMixedIn;
    final landedAt = _browser.index;
    if (landedAt != _index) {
      // A landing no event told of: the writer's own step, or another,
      // which the app follows.
      if (landedAt == target && _didOwnStepLand(landedAt)) return;
      if (_stepTarget != null) {
        _endStep(didLand: false);
        _followUser();
      }
      return;
    }
    _endStep(didLand: false);
    // The user's step landed, which the app did not follow, and the
    // writer's never did: the writer brings the browser back to the
    // entries the app shows.
    final wanted = _lastWanted;
    if (wasUserStepMixedIn && _queue.isEmpty && wanted != null) {
      _queue.add(wanted);
    }
  }

  void _endStep({required bool didLand}) {
    _landingTimer?.cancel();
    _landingTimer = null;
    _stepTarget = null;
    _isAppStep = false;
    _isUserStepMixedIn = false;
    final landing = _landing;
    _landing = null;
    landing?.complete(didLand);
  }
}

sealed class _Work {
  const new();
}

final class _Entries extends _Work {
  const new(this.entries, {required this.isReplace});

  final List<UrlState> entries;

  // Whether the app reported the last entry as a replace.
  final bool isReplace;
}

final class _Step extends _Work {
  const new(this.delta);

  final int delta;
}
