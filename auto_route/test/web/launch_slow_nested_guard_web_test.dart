// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/held_guard.dart';
import 'browser_history.dart';

// On the web, an app opened at a link to a page inside a shell whose guard
// is slow keeps the one browser entry the browser made for the link, while
// the guard decides and after it says yes: the pages the link opens under
// the guarded page, Home's first page and the shell's first page, share
// that entry.
//
// Before, the page the link opens was not open yet while its guard
// decided, so the history no longer counted its entry as the link's: the
// first page of Home got an entry of its own under it while the guard
// decided, and the shell's first page another after the "yes", three
// entries for one launch. The back button then walked through pages the
// user never navigated to.
//
// The steps: the app opened at /mail/77, with prefix matches, so the link
// opens Home and Mail with Inbox under message 77; the guard of message 77
// holds its answer, then says yes.
//
// Native behavior this holds to: Flutter's Router reports its first route
// over the entry the app was opened on (router.dart:
// routerReportsNewRouteInformation with replace true updates the current
// history entry), so one launch is one entry. No source is quoted for the
// browser making one entry for a url it opens.
late HeldGuard _guard;

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'FeedRoute',
          path: '',
          builder: (_, _) => const Text('Feed'),
        ),
      ],
    ),
    NamedRouteDef(
      name: 'MailRoute',
      path: '/mail',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'InboxRoute',
          path: '',
          builder: (_, _) => const Text('Inbox'),
        ),
        NamedRouteDef(
          name: 'MessageRoute',
          path: ':id',
          guards: [_guard],
          builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
        ),
      ],
    ),
  ],
);

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);
  setUp(() => _guard = HeldGuard());

  testWidgets('opened at /mail/77, the slow guard of message 77 says yes', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    final first = browserSerialCount < 0 ? 0 : browserSerialCount;
    String reading() => '(${browserSerialCount - first}, $browserPath)';
    openBrowserAt(tester, '/mail/77');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(
        routerConfig: router.config(includePrefixMatches: true),
      ),
    );
    await settleBrowser(tester);
    final readings = [reading()];
    await _guard.asks.lastOrNull?.allow();
    await settleBrowser(tester);
    readings.add(reading());
    expect(find.text('Mail 77'), findsOneWidget);
    expect(readings, ['(0, /mail/77)', '(0, /mail/77)']);
  });
}
