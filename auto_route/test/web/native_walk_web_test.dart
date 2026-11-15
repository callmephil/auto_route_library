// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_history.dart';
import 'native_walk.dart';

// On the web, the browser's back button walks the pages the way the system
// back does on a phone: each press closes the page on top, and a page the app
// closed never comes back.
//
// Native behavior this holds to: Flutter's Navigator under Android's system
// back and the iOS back gesture, which reach the app as
// RouterDelegate.popRoute; see native_walk.dart, which runs both walks and
// compares them.
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  // Steps: open the pages over Home, make the call, then press the browser's
  // back button down to the first entry and its forward button up again.
  for (final (label, opens, call) in <(String, List<String>, WalkCall)>[
    (
      'a push',
      ['ARoute'],
      (router) => unawaited(router.push(const NamedRoute('BRoute'))),
    ),
    ('a pop', ['ARoute', 'BRoute'], (router) => router.pop()),
    (
      'a replace',
      ['ARoute', 'BRoute'],
      (router) => unawaited(router.replace(const NamedRoute('CRoute'))),
    ),
  ]) {
    testWidgets('On web, after $label the back button shows the pages the '
        'system back shows', (tester) async {
      await expectNativeWalk(tester, opens: opens, calls: [call]);
    });
  }

  // Steps: open A, B and C over Home, call navigate to A, which is under B
  // and C, then press the browser's back button.
  // Is: navigate takes B and C off the stack without a pop, the history
  // writes '/a' as a new entry over C's, and the back button shows C and B
  // again, pages the app closed.
  testWidgets(
    'On web, after navigate to a page underneath the back button shows no '
    'page the app closed',
    (tester) async {
      await expectNativeWalk(
        tester,
        opens: ['ARoute', 'BRoute', 'CRoute'],
        calls: [
          (router) => unawaited(router.navigate(const NamedRoute('ARoute'))),
        ],
      );
    },
    // The web history keeps the entry of a page removed without a pop under
    // the page on top, on every browser; the fix that drops it runs this.
    skip: true,
  );
}
