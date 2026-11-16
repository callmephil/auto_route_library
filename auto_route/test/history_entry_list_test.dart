import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/history_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_sequences.dart';
import 'router_test_utils.dart';

// The entries the browser's history should hold after calls on a router,
// as HistoryEntryList keeps them from the url states the router reports, with
// no browser: the list is the web history's account of what back must walk.
//
// Each row is a sequence of calls and the urls of the entries it must leave,
// the app's first entry first. The expected entries are not taken from the
// list: they are the entries Chrome held after the same calls made a frame
// apart, as the review's probes of the web history recorded them, or, in the
// rows marked native, what Flutter's Navigator holds, where the recorded
// entries kept a page the app had closed. Every row runs a frame apart, in
// one turn and microtasks apart, and must leave the same entries each way.
//
// Native behavior this holds to: Flutter's Navigator, which Android's system
// back and the iOS back gesture walk. Back closes the page on top; a page
// that was popped, replaced or removed never comes back; pushReplacement
// leaves the page under as the way back; pushAndRemoveUntil leaves only the
// routes it kept. An entry of its own for each tab shown and for
// history.pushState is the web's, the HTML History API.
class _ListHistory extends NavigationHistory {
  new(this.router);

  @override
  final StackRouter router;

  late final list = HistoryEntryList(
    isPageOpen: (pageId) => controllerOfPage(pageId) != null,
  );

  @override
  void onNewUrlState(UrlState newState, {bool notify = true}) {
    final shown = list.show(newState);
    super.onNewUrlState(
      shown.copyWith(shouldReplace: newState.shouldReplace),
      notify: notify,
    );
  }

  @override
  void pushPathState(Object? state) {
    final newState = UrlState(
      urlState.uri,
      urlState.segments,
      pathState: state,
    );
    if (newState == urlState) return;
    list.add(newState);
    super.onNewUrlState(newState);
  }

  @override
  Object? get pathState => urlState.pathState;

  @override
  bool get canNavigateBack => length > 1;

  @override
  int get length => list.entries.length;

  @override
  void back() => throw UnimplementedError();

  @override
  void forward() => throw UnimplementedError();
}

Future<List<String>> _entriesAfter(
  WidgetTester tester,
  HistoryRow row,
  CallGap gap, {
  required bool isGuarded,
}) async {
  final (opens, calls, _) = row;
  final router = HistoryRouter(isGuarded: isGuarded, history: _ListHistory.new);
  final history = router.navigationHistory as _ListHistory;
  addTearDown(history.dispose);
  await pumpRouterApp(tester, router);
  for (final name in opens) {
    unawaited(router.push(NamedRoute(name)));
    await tester.pumpAndSettle();
  }
  for (final (index, call) in calls.indexed) {
    call(router);
    if (index == calls.length - 1) break;
    switch (gap) {
      case .frame:
        await tester.pumpAndSettle();
      case .none:
        break;
      case .microtasks:
        for (var i = 0; i < 30; i++) {
          await Future<void>.value();
        }
    }
  }
  await tester.pumpAndSettle();
  return [
    for (final entry in history.list.entries)
      if (entry.url.isEmpty) '/' else entry.url,
  ];
}

void main() {
  for (final (source, rows) in [
    ('as Chrome held them a frame apart', recordedSequences),
    ('once worse than a frame apart', onceWorseSequences),
    ('as the Navigator holds them', nativeSequences),
  ]) {
    group('The entries $source:', () {
      for (final MapEntry(key: name, value: row) in rows.entries) {
        for (final (label, gap) in [
          ('a frame apart', CallGap.frame),
          ('in one turn', CallGap.none),
          ('microtasks apart', CallGap.microtasks),
        ]) {
          testWidgets('$name, $label', (tester) async {
            expect(
              await _entriesAfter(tester, row, gap, isGuarded: false),
              row.$3,
            );
          });
        }
        testWidgets('$name, in one turn, with guards that answer at once', (
          tester,
        ) async {
          expect(
            await _entriesAfter(tester, row, .none, isGuarded: true),
            row.$3,
          );
        });
      }
    });
  }

  group('The entries where the router reports a replace:', () {
    for (final MapEntry(key: name, value: row) in replaceSequences.entries) {
      testWidgets(name, (tester) async {
        expect(
          await _entriesAfter(tester, row, .frame, isGuarded: false),
          row.$3,
        );
      });
    }
  });
}
