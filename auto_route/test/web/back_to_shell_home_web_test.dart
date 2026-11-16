@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/held_guard.dart';
import 'browser_history.dart';

// On the web, the browser's back button from a page that holds a nested
// router to Home, a shell at the root path, wrote a new entry for Home: the
// browser stood at its third entry instead of its first, the page left lost
// its forward entry, and the next back seemed to do nothing.
// Setup: Home at the root path holds a nested router on Feed. Mail holds a
// nested router with Message by id, with no guard, a guard that says yes at
// once, a guard that answers later, or a global guard that says yes at once.
// Steps: the app calls navigatePath to message 77. Then the browser's back
// button, then its forward button.
// Was: after back, Home at the third entry, with no entry ahead.
// Should: after back, Home at the first entry, and forward shows the
// message again at the second.
// Native behavior this holds to: the HTML standard's traversal moves to the
// entry before and keeps the one after it as a forward entry; back never
// adds an entry.
enum _Guard { none, yesAtOnce, yesLater, globalYesAtOnce }

RootStackRouter _router(
  HeldGuard? held, {
  required bool isGuarded,
  required bool hasGlobalGuard,
}) => .build(
  guards: [
    if (hasGlobalGuard) AutoRouteGuard.simple((resolver, _) => resolver.next()),
  ],
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
          guards: [
            if (isGuarded)
              AutoRouteGuard.simple((resolver, _) => resolver.next()),
            ?held,
          ],
          builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
        ),
      ],
    ),
  ],
);

String _browser() => '($browserSerialCount, $browserPath)';

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  for (final guard in _Guard.values) {
    testWidgets('Back from Mail to the shell Home, ${guard.name}, keeps the '
        'browser on its entries', (tester) async {
      final held = guard == .yesLater ? HeldGuard() : null;
      final router = _router(
        held,
        isGuarded: guard == .yesAtOnce,
        hasGlobalGuard: guard == .globalYesAtOnce,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: router.config()),
      );
      await settleBrowser(tester);

      unawaited(router.navigatePath('/mail/77'));
      await settleBrowser(tester);
      if (held != null) {
        await held.last.allow();
        await settleBrowser(tester);
      }
      expect(_browser(), '(1, /mail/77)');

      await pressBrowserBack(tester);

      expect(router.stack.map((page) => page.name), ['HomeRoute']);
      expect(find.text('Feed'), findsOneWidget);
      expect(_browser(), '(0, /)');

      await pressBrowserForward(tester);
      // Forward opens the message again, and asks its guard again.
      if (held != null) {
        await held.last.allow();
        await settleBrowser(tester);
      }

      expect(
        (find.text('Mail 77').evaluate().length, _browser()),
        (1, '(1, /mail/77)'),
        reason: 'forward shows the message on its entry again',
      );
    });
  }
}
