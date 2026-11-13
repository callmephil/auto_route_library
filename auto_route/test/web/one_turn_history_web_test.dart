// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, several navigations in one turn leave the browser's history as
// the same calls one after another would: each page still open has an entry,
// and the browser's back button walks back through them. The router writes
// the url once a frame, after it, so each pair of calls in one turn is a case
// of its own for the web history.
//
// Native behavior this holds to: the HTML History API, whose pushState and
// replaceState change the history at once, one call after another; and
// Flutter's own Navigator with reportsRouteUpdateToEngine, which writes each
// change to the engine as it flushes (Navigator._flushHistoryUpdates).
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
      ('DRoute', '/d'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
    NamedRouteDef(
      name: 'ItemRoute',
      path: '/item',
      builder: (_, data) => Text('Item ${data.args ?? 'none'}'),
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const AutoRouter(),
      children: [
        NamedRouteDef(
          name: 'InboxRoute',
          path: '',
          builder: (_, _) => const Text('InboxRoute'),
        ),
        NamedRouteDef(
          name: 'MessageRoute',
          path: ':id',
          builder: (_, _) => const Text('MessageRoute'),
        ),
      ],
    ),
  ],
);

// Opens A over Home, each step in a turn of its own.
final _onA = <void Function(RootStackRouter router)>[
  (router) => unawaited(router.push(const NamedRoute('ARoute'))),
];

// Opens B over the page on top.
void _openB(RootStackRouter router) =>
    unawaited(router.push(const NamedRoute('BRoute')));

// The browser's entry, counted from [home]'s, its url, and the names on the
// router's stack.
(int, String, String) _shown(RootStackRouter router, int home) => (
  browserSerialCount - home,
  browserPath,
  router.stack.map((page) => page.name).join(' '),
);

// Runs [calls] in one turn from Home, after each of [opens] in a turn of its
// own, and checks what the browser and the router show after them.
// Then it presses the browser's back button once for each further reading in
// [expected], and checks those too. The first reading is checked before the
// browser moves, since a back step from a missing entry would leave the test
// page and nothing would ever answer.
Future<void> _expectAfter(
  WidgetTester tester,
  void Function(RootStackRouter router) calls,
  List<(int, String, String)> expected, {
  List<void Function(RootStackRouter router)> opens = const [],
  bool Function(String? location)? neglectWhen,
}) async {
  final [expectedAfterCalls, ...expectedAfterBacks] = expected;
  final router = _router();
  await pumpRouterConfigApp(tester, router.config(neglectWhen: neglectWhen));
  await settleBrowser(tester);
  final home = browserSerialCount;
  for (final open in opens) {
    open(router);
    await settleBrowser(tester);
  }
  calls(router);
  await settleBrowser(tester);
  final afterCalls = _shown(router, home);
  // The Chrome runner doesn't print a failed expectation.
  printOnFailure('after the calls: $afterCalls');
  expect(afterCalls, expectedAfterCalls);

  final afterBacks = <(int, String, String)>[];
  for (var i = 0; i < expectedAfterBacks.length; i++) {
    await pressBrowserBack(tester);
    afterBacks.add(_shown(router, home));
  }
  printOnFailure('after each back: $afterBacks');
  expect(afterBacks, expectedAfterBacks);
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('On web, three pushes in one turn get an entry each', (
    tester,
  ) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('ARoute')));
        unawaited(router.push(const NamedRoute('BRoute')));
        unawaited(router.push(const NamedRoute('CRoute')));
      },
      [
        (3, '/c', 'HomeRoute ARoute BRoute CRoute'),
        (2, '/b', 'HomeRoute ARoute BRoute'),
        (1, '/a', 'HomeRoute ARoute'),
        (0, '/', 'HomeRoute'),
      ],
    );
  });

  testWidgets('On web, a push, a pop and a push in one turn leave one entry '
      'over Home', (tester) async {
    await _expectAfter(tester, (router) {
      unawaited(router.push(const NamedRoute('ARoute')));
      router.pop();
      unawaited(router.push(const NamedRoute('BRoute')));
    }, [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')]);
  });

  testWidgets('On web, a push, a replace and a push in one turn get an entry '
      'for each page left', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('ARoute')));
        unawaited(router.replace(const NamedRoute('BRoute')));
        unawaited(router.push(const NamedRoute('CRoute')));
      },
      [
        (2, '/c', 'HomeRoute BRoute CRoute'),
        (1, '/b', 'HomeRoute BRoute'),
        (0, '/', 'HomeRoute'),
      ],
    );
  });

  testWidgets('On web, two pages of one route with other arguments, pushed '
      'in one turn, get an entry each', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('ItemRoute', args: 1)));
        unawaited(router.push(const NamedRoute('ItemRoute', args: 2)));
      },
      [
        (2, '/item', 'HomeRoute ItemRoute ItemRoute'),
        (1, '/item', 'HomeRoute ItemRoute'),
        (0, '/', 'HomeRoute'),
      ],
    );
  });

  testWidgets('On web, a push and a pushPathState in one turn get an entry '
      'each', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('BRoute')));
        router.pushPathState('filter');
      },
      [
        (2, '/b', 'HomeRoute BRoute'),
        (1, '/b', 'HomeRoute BRoute'),
        (0, '/', 'HomeRoute'),
      ],
    );
  });

  testWidgets('On web, pushAndPopUntil down to Home takes the entry of the '
      'page it closes', (tester) async {
    await _expectAfter(
      tester,
      (router) => unawaited(
        router.pushAndPopUntil(
          const NamedRoute('BRoute'),
          predicate: (route) => route.settings.name == 'HomeRoute',
        ),
      ),
      [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });

  testWidgets('On web, two pushes and a pop in one turn leave an entry for '
      'the page left on top', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('BRoute')));
        unawaited(router.push(const NamedRoute('CRoute')));
        router.pop();
      },
      [
        (2, '/b', 'HomeRoute ARoute BRoute'),
        (1, '/a', 'HomeRoute ARoute'),
        (0, '/', 'HomeRoute'),
      ],
      opens: _onA,
    );
  });

  testWidgets('On web, two pushes in one turn, the first to a url the app '
      'keeps out of the address bar, get one entry', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('ARoute')));
        unawaited(router.push(const NamedRoute('BRoute')));
      },
      [(1, '/b', 'HomeRoute ARoute BRoute'), (0, '/', 'HomeRoute')],
      neglectWhen: (location) => location == '/a',
    );
  });

  // From A, replaceAll with C and a push of B in the same turn, then the
  // browser's back button. Was: C got no entry, since the router wrote only
  // B, over A's entry, so back from B went to Home's entry and put Home on
  // top of C and B.
  testWidgets('On web, a replaceAll and a push in one turn get an entry '
      'each', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.replaceAll(const [NamedRoute('CRoute')]));
        unawaited(router.push(const NamedRoute('BRoute')));
      },
      [(2, '/b', 'CRoute BRoute'), (1, '/c', 'CRoute')],
      opens: _onA,
    );
  });
  // From A, popAndPush of B, then the browser's back button. Was: the step
  // back after the pop waited a microtask and counted from the app's entry,
  // which the push in the same turn had already moved, so it made no step and
  // the router wrote B as a new entry over A's. Back from B then reopened A
  // on top of B.
  testWidgets('On web, popAndPush takes the entry of the page it pops', (
    tester,
  ) async {
    await _expectAfter(
      tester,
      (router) => unawaited(router.popAndPush(const NamedRoute('BRoute'))),
      [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });
  // From A over Home, popUntilRoot and a push of B in one turn.
  testWidgets('On web, popUntilRoot and a push in one turn leave no entry of '
      'the popped page', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        router.popUntilRoot();
        unawaited(router.push(const NamedRoute('BRoute')));
      },
      [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });

  // From B over A over Home, popUntilRoot and a push of C in one turn.
  testWidgets('On web, popUntilRoot over two pages and a push in one turn '
      'show the pushed page', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        router.popUntilRoot();
        unawaited(router.push(const NamedRoute('CRoute')));
      },
      [(1, '/c', 'HomeRoute CRoute'), (0, '/', 'HomeRoute')],
      opens: [
        ..._onA,
        (router) => unawaited(router.push(const NamedRoute('BRoute'))),
      ],
    );
  });

  // From Mail with a message open in its nested router, a pop of the
  // message and a push of A on the root, in one turn.
  testWidgets('On web, a pop in a nested router and a push on the root in one '
      'turn leave no entry of the popped page', (tester) async {
    StackRouter mail(RootStackRouter router) =>
        router.innerRouterOf('MailRoute')!;
    await _expectAfter(
      tester,
      (router) {
        mail(router).pop();
        unawaited(router.push(const NamedRoute('ARoute')));
      },
      [
        (2, '/a', 'HomeRoute MailRoute ARoute'),
        (1, '/mail', 'HomeRoute MailRoute'),
      ],
      opens: [
        (router) => unawaited(router.push(const NamedRoute('MailRoute'))),
        (router) => unawaited(
          mail(router)
              .push(const NamedRoute('MessageRoute', params: {'id': '1'})),
        ),
      ],
    );
  });

  // From A over Home, a replace of A with B and a push of C in one turn.
  testWidgets('On web, a replace and a push in one turn give each page an '
      'entry', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.replace(const NamedRoute('BRoute')));
        unawaited(router.push(const NamedRoute('CRoute')));
      },
      [
        (2, '/c', 'HomeRoute BRoute CRoute'),
        (1, '/b', 'HomeRoute BRoute'),
        (0, '/', 'HomeRoute'),
      ],
      opens: _onA,
    );
  });
  // From A over Home, a replace of A with B and a pop of B in one turn. Was:
  // the pop of B, never shown, rebuilt Home's url as a new entry over A's,
  // so the browser stood on a third entry, with A's still under it.
  testWidgets('On web, a replace and a pop in one turn end on the entry of '
      'the page under', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.replace(const NamedRoute('BRoute')));
        router.pop();
      },
      [(0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });
  // From A over Home, a replace of A with B, a push of C and a pop, in one
  // turn. Was: the browser held '/', '/b', '/c', '/b', and back showed C.
  testWidgets('On web, a replace, a push and a pop in one turn end on the '
      "replacing page's entry", (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.replace(const NamedRoute('BRoute')));
        unawaited(router.push(const NamedRoute('CRoute')));
        router.pop();
      },
      [(1, '/b', 'HomeRoute BRoute'), (0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });

  // From A over Home, a replace of A with B, a pop and a push of C, in one
  // turn. Was: C went over Home's entry, and back had nowhere to go.
  testWidgets('On web, a replace, a pop and a push in one turn give the pushed '
      'page an entry of its own', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.replace(const NamedRoute('BRoute')));
        router.pop();
        unawaited(router.push(const NamedRoute('CRoute')));
      },
      [(1, '/c', 'HomeRoute CRoute'), (0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });

  // From B over A over Home, two popAndPush, of C and then of D, in one turn.
  // Was: D took A's entry, and back from D skipped A.
  testWidgets('On web, two popAndPush in one turn keep the entry of the page '
      'under', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.popAndPush(const NamedRoute('CRoute')));
        unawaited(router.popAndPush(const NamedRoute('DRoute')));
      },
      [
        (2, '/d', 'HomeRoute ARoute DRoute'),
        (1, '/a', 'HomeRoute ARoute'),
        (0, '/', 'HomeRoute'),
      ],
      opens: [..._onA, _openB],
    );
  });

  // From B over A over Home, popUntilRoot and two pushes, of C and D, in one
  // turn. Was: back from D reopened A, a page popUntilRoot had closed.
  testWidgets('On web, popUntilRoot and two pushes in one turn leave no entry '
      'of a closed page', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        router.popUntilRoot();
        unawaited(router.push(const NamedRoute('CRoute')));
        unawaited(router.push(const NamedRoute('DRoute')));
      },
      [
        (2, '/d', 'HomeRoute CRoute DRoute'),
        (1, '/c', 'HomeRoute CRoute'),
        (0, '/', 'HomeRoute'),
      ],
      opens: [..._onA, _openB],
    );
  });

  // From A over Home, two pushes, of B and C, and popUntilRoot, in one turn.
  // Was: the browser stood on a fourth entry, with A's, B's and C's under it.
  testWidgets('On web, two pushes and popUntilRoot in one turn end on the '
      'entry of Home', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        unawaited(router.push(const NamedRoute('BRoute')));
        unawaited(router.push(const NamedRoute('CRoute')));
        router.popUntilRoot();
      },
      [(0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });
  // From A over Home, a pop, a push of A again and a pop, in one turn. Was:
  // the browser held '/', '/a', '/', and back showed A, a page already
  // closed: the push of A, whose url the browser still showed, was taken for
  // the browser's own move.
  testWidgets('On web, a pop, a push of the same page again and a pop in one '
      'turn end on the entry of Home', (tester) async {
    await _expectAfter(
      tester,
      (router) {
        router.pop();
        unawaited(router.push(const NamedRoute('ARoute')));
        router.pop();
      },
      [(0, '/', 'HomeRoute')],
      opens: _onA,
    );
  });
}
