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
}

/// Brings a browser's history to the entries the app should have, one
/// operation at a time, as the browser's one writer.
///
/// [bringTo] takes the entries wanted, from the app's first entry to the one
/// of the page on top, and queues them. The writer works through the queue
/// in order. For each it finds the first entry the browser holds otherwise:
///
/// * none, and the browser stands elsewhere: it steps to the last entry
///   wanted, which leaves the entries after it ahead, as history.back does;
/// * the entry the browser stands on: it writes over it, then adds the rest;
/// * an entry under it: it steps back to the entry before that one and adds
///   from there, so nothing stale stays on the way back; the app's first
///   entry has none before it and is written over.
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
    required this.onUserMove,
    this.landingLimit = const Duration(seconds: 1),
  }) : _first = _browser.index,
       _index = _browser.index;

  final HistoryBrowser _browser;

  /// Called when the browser moved without the writer asking it to.
  final void Function() onUserMove;

  /// How long the writer waits for a step to land before it reads where the
  /// browser stands, as after a step the browser had no entry for.
  final Duration landingLimit;

  // What each browser entry holds, by its number, as far as known.
  final _entries = <int, UrlState>{};

  final _queue = Queue<_Work>();

  int _first;
  int _index;

  // The entry a step of the writer's own is on its way to, and what ends the
  // wait for it: true when it landed there.
  int? _stepTarget;
  int _stepDelta = 0;
  Completer<bool>? _landing;
  Timer? _landingTimer;

  // Whether the step on its way was asked for by the app, with [step]: its
  // landing is followed like the user's.
  bool _isAppStep = false;

  // The url of the entry a step of the writer's own landed on, until the
  // platform's report of that landing is taken.
  String? _ownLandingUrl;

  bool _isRunning = false;
  bool _isWriting = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // Counts the moves the writer did not ask for, so that work under way
  // when one came stops.
  int _userMoves = 0;

  Completer<void>? _idle;

  /// The number of the app's first entry: the entry the browser stood on
  /// when the app started, or a lower one the user has stepped back to.
  int get first => _first;

  /// The number of the entry the browser stands on, as far as the writer
  /// knows: it has not heard of a step of the user's that is still on its
  /// way.
  int get index => _index;

  /// Whether the writer has nothing left to do.
  bool get isIdle => !_isRunning && _queue.isEmpty;

  /// What the browser entry with the number [number] holds, or null when the
  /// writer never wrote it, as an entry from before a reload.
  UrlState? entryAt(int number) => _entries[number];

  /// Completes once the writer has nothing left to do.
  Future<void> whenIdle() {
    if (isIdle) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Holds the work back until [resume], as while no Router shows the app
  /// and nothing can be written.
  void pause() => _isPaused = true;

  /// Takes up the work again after [pause].
  void resume() {
    _isPaused = false;
    _run();
  }

  /// Stops the writer for good.
  void dispose() {
    _isDisposed = true;
    _queue.clear();
    _endStep(didLand: false);
    _completeIdle();
  }

  /// Queues [entries], the app's first entry first, as what the browser
  /// should hold up to the entry it stands on.
  void bringTo(List<UrlState> entries) {
    if (entries.isEmpty || _isDisposed) return;
    _queue.add(_Entries(List.unmodifiable(entries)));
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
    if (_didOwnStepLand(landedAt)) _ownLandingUrl = _browser.url;
  }

  /// Whether [reported], a route the platform just reported, only tells of
  /// a step the writer made itself, so the app has nothing to follow.
  ///
  /// The report and [browserLanded] come in either order, and the Router
  /// drops a report when a newer one comes while it is parsed, so each is
  /// taken on its own: the step counts as landed by whichever comes first.
  bool isOwnStep(UrlState reported) {
    if (_isDisposed) return false;
    final landedAt = _browser.index;
    final ownLandingUrl = _ownLandingUrl;
    _ownLandingUrl = null;
    if (ownLandingUrl != null &&
        isSameHistoryUrl(ownLandingUrl, reported.url)) {
      return true;
    }
    // The report came before the browser's event. While the writer writes,
    // the browser's number is behind the writer's own account, and only the
    // event tells of a move.
    if (_isWriting || landedAt == _index) return false;
    return _didOwnStepLand(landedAt);
  }

  // The browser landed on the entry [landedAt], which it did not stand on
  // before. Returns whether that is the step the writer asked for, for
  // itself; any other landing is followed by the app.
  bool _didOwnStepLand(int landedAt) {
    final isStep = landedAt == _stepTarget;
    if (isStep && !_isAppStep) {
      _index = landedAt;
      _endStep(didLand: true);
      return true;
    }
    if (isStep) {
      _endStep(didLand: false);
    } else if (_stepTarget != null) {
      // A step of the user's landed first. The browser counts the writer's
      // step, still on its way, from there.
      _stepTarget = landedAt + _stepDelta;
    }
    _followUser();
    return false;
  }

  /// Notes that the browser entry with the number [number] now holds
  /// [entry], as when the app shows the page of the entry the user moved to.
  void adopt(int number, UrlState entry) => _entries[number] = entry;

  // The browser moved without the writer asking: the user did, or the app
  // through [step]. What was still to do no longer fits where the browser
  // stands, and the app follows. A step of the writer's that is still on its
  // way keeps the work waiting until it lands too.
  void _followUser() {
    _userMoves++;
    _ownLandingUrl = null;
    _queue.clear();
    _index = _browser.index;
    if (_index < _first) _first = _index;
    final held = _entries[_index];
    if (held != null && !isSameHistoryUrl(held.url, _browser.url)) {
      // The browser made a new entry here, as for a url typed into the
      // address bar, which dropped the ones after it.
      _entries.removeWhere((number, _) => number >= _index);
    }
    onUserMove();
  }

  void _run() {
    if (_isRunning || _isPaused || _isDisposed) return;
    _isRunning = true;
    unawaited(_work());
  }

  Future<void> _work() async {
    try {
      // After the turn, so the changes made in it are all in the queue.
      await Future<void>.value();
      while (_queue.isNotEmpty && !_isPaused && !_isDisposed) {
        switch (_nextWork()) {
          case _Entries(:final entries):
            await _reach(entries);
          case _Step(:final delta):
            await _stepFor(app: true, delta);
        }
      }
    } finally {
      _isRunning = false;
      if (_queue.isEmpty) _completeIdle();
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

  // Brings the browser to [entries]; stops when the user moves it meanwhile.
  Future<void> _reach(List<UrlState> entries) async {
    // A move of the user's that no event told of.
    if (_browser.index != _index) {
      _followUser();
      return;
    }
    final userMoves = _userMoves;
    final unheld = _firstUnheld(entries);
    if (unheld == null) {
      final top = _first + entries.length - 1;
      if (_index != top) await _stepFor(top - _index);
      if (userMoves == _userMoves) _adoptAll(entries, entries.length);
      return;
    }
    final at = _first + unheld;
    // Written over where it is the entry the browser stands on, or the
    // app's first, which has nothing before it to step back to.
    final replaces = at == _index || (at < _index && unheld == 0);
    final from = replaces ? at : at - 1;
    if (from != _index && !await _stepFor(from - _index)) return;
    if (userMoves != _userMoves) return;
    _adoptAll(entries, unheld);
    _isWriting = true;
    try {
      for (final (offset, entry) in entries.skip(unheld).indexed) {
        _write(entry, replaces: replaces && offset == 0);
      }
      await _browser.whenWritten();
    } finally {
      _isWriting = false;
    }
  }

  // The place in [entries] of the first one the browser holds otherwise, or
  // not at all; null when it holds them all.
  int? _firstUnheld(List<UrlState> entries) {
    for (final (offset, entry) in entries.indexed) {
      if (!_holds(_first + offset, entry)) return offset;
    }
    return null;
  }

  // Whether the browser entry [number] holds the url and path state of
  // [entry]. An entry the writer never wrote, as the one the app starts on,
  // can be read only while the browser stands on it.
  bool _holds(int number, UrlState entry) {
    final held = _entries[number];
    if (held != null) {
      return isSameHistoryUrl(held.url, entry.url) &&
          held.pathState == entry.pathState;
    }
    return number == _index &&
        isSameHistoryUrl(_browser.url, entry.url) &&
        _browser.state == entry.pathState;
  }

  // Notes the first [count] of [entries] as what the browser holds: the same
  // urls, for pages that may have been opened anew.
  void _adoptAll(List<UrlState> entries, int count) {
    for (final (offset, entry) in entries.take(count).indexed) {
      _entries[_first + offset] = entry;
    }
  }

  void _write(UrlState entry, {required bool replaces}) {
    assert(
      _stepTarget == null,
      'Nothing is written while a step is on its way.',
    );
    if (!replaces) {
      _index++;
      _entries.removeWhere((number, _) => number >= _index);
    }
    _entries[_index] = entry;
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
    if (_stepTarget == null) return;
    final landedAt = _browser.index;
    if (landedAt != _index && _didOwnStepLand(landedAt)) return;
    _endStep(didLand: false);
  }

  void _endStep({required bool didLand}) {
    _landingTimer?.cancel();
    _landingTimer = null;
    _stepTarget = null;
    _isAppStep = false;
    final landing = _landing;
    _landing = null;
    landing?.complete(didLand);
  }
}

sealed class _Work {
  const new();
}

final class _Entries extends _Work {
  const new(this.entries);

  final List<UrlState> entries;
}

final class _Step extends _Work {
  const new(this.delta);

  final int delta;
}
