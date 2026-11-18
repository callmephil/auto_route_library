import 'dart:async';
import 'dart:collection';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_writer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A browser history for tests of the web history on the VM: it holds
/// entries as a browser does and lands a step only when the test says so.
///
/// It follows Chrome: a write goes to the entry it stands on, a new entry
/// drops the ones ahead, and a step is counted from where the browser
/// stands or, while another step is on its way, from where that one is
/// going.
class TestHistoryBrowser implements HistoryBrowser {
  /// Every entry the browser holds, as its url and state.
  final entries = <(String, Object?)>[('/', null)];

  /// What was asked of the browser, in order.
  final asked = <String>[];

  // The entries the steps on their way are going to.
  final _steps = Queue<int>();

  /// The number of the entry the browser's writer believes it stands on,
  /// when the test checks where the writer writes.
  int Function()? writerIndex;

  /// Called after each landing, as the engine reports the entry to the app.
  void Function()? onLanded;

  @override
  int index = 0;

  /// Whether a step is lost, as when the browser has no such entry.
  bool losesSteps = false;

  /// Whether a write is lost, as with a route information provider that
  /// writes no browser entry.
  bool losesWrites = false;

  /// Whether a step is on its way.
  bool get isStepping => _steps.isNotEmpty;

  @override
  String get url => entries.elementAtOrNull(index)?.$1 ?? '';

  @override
  Object? get state => entries.elementAtOrNull(index)?.$2;

  @override
  void write(UrlState entry, {required bool replaces}) {
    // A write goes to the entry the browser stands on. The writer must know
    // which that is: before a step of its own has landed it is still the
    // entry being left.
    if (writerIndex case final believed? when !losesWrites) {
      expect(
        index,
        believed() - (replaces ? 0 : 1),
        reason: 'written on an entry the writer did not know it stood on',
      );
    }
    asked.add('${replaces ? 'replace' : 'push'} ${entry.url}');
    if (losesWrites) return;
    if (replaces) {
      entries.removeAt(index);
    } else {
      index++;
      entries.removeRange(index, entries.length);
    }
    entries.insert(index, (entry.url, entry.pathState));
  }

  @override
  Future<void> whenWritten() => .value();

  @override
  void go(int delta) {
    asked.add('go $delta');
    _didStartStep(delta);
  }

  // From the entry the browser stands on, or is going to.
  @override
  bool get canGoForward => (_steps.lastOrNull ?? index) < entries.length - 1;

  /// The user presses the back button; false when no entry is under the one
  /// the browser stands on, or is going to.
  bool didPressBack() => _didStartStep(-1);

  /// The user presses the forward button; false when no entry is ahead.
  bool didPressForward() => _didStartStep(1);

  /// The user goes [delta] entries through the history at once, as from
  /// the list a long press on the back or forward button shows; false when
  /// the browser has no such entry.
  bool didJump(int delta) => _didStartStep(delta);

  bool _didStartStep(int delta) {
    final to = (_steps.lastOrNull ?? index) + delta;
    if (losesSteps || to < 0 || to >= entries.length) return false;
    _steps.add(to);
    return true;
  }

  @override
  bool keepsOut(UrlState entry) => entry.url.startsWith('/kept');

  @override
  bool get canWrite => true;

  @override
  bool keepsEntries = true;

  @override
  void listen(void Function() onLanding) => _onLanding = onLanding;

  @override
  void close() => _onLanding = null;

  void Function()? _onLanding;

  /// The browser lands the oldest step on its way and tells its listener,
  /// then the app.
  void land() {
    landUntold();
    _onLanding?.call();
    onLanded?.call();
  }

  /// Makes [onLanded] report each entry the browser lands on to the app that
  /// [tester] runs, as the engine does for a popstate event: through
  /// `pushRouteInformation` on the `flutter/navigation` channel, which
  /// reaches the app's Router.
  void reportLandingsTo(WidgetTester tester) {
    onLanded = () => unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', {'location': url, 'state': state}),
        ),
        null,
      ),
    );
  }

  /// Runs the frames of the app that [tester] runs and lands every step on
  /// its way, until the browser holds what the app shows.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (isStepping) {
      land();
      await tester.pumpAndSettle();
    }
  }

  /// The browser lands the oldest step on its way; its event is still to
  /// come.
  void landUntold() => index = _steps.removeFirst();

  /// The urls of every entry, with the one the browser stands on marked.
  String get held => [
    for (final (number, (entryUrl, saved)) in entries.indexed)
      '${number == index ? '>' : ''}$entryUrl${saved == null ? '' : '#$saved'}',
  ].join(' ');
}
