import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, the browser's back button from a page that holds a nested
// router to Home, a shell at '/', steps back to Home's own entry and keeps
// the page left as the entry ahead, which forward opens again.
// Native behavior this holds to: the HTML standard's traversal moves to the
// entry before and keeps the next one as a forward entry; back never adds
// an entry.
// Headless test: auto_route/test/web/back_to_shell_home_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back to shell home', () {
    Widget page(String name) => Scaffold(
      body: SafeArea(child: Center(child: Text(name))),
    );

    // Steps: Home at '/' holds a nested router on Feed. The app calls
    // navigatePath to message 77 of Mail, which holds a router too. Then the
    // browser's back button, then its forward button.
    // Was: after back, the browser on a new entry for '/', with nothing
    // ahead.
    // Should: back goes one entry back, to '/', and forward one entry
    // forward, to the message.
    testWidgets(
      'Back from Mail to the shell Home goes one entry back',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef.shell(
              name: 'HomeRoute',
              path: '/',
              children: [
                NamedRouteDef(
                  name: 'FeedRoute',
                  path: '',
                  builder: (_, _) => page('FeedRoute'),
                ),
              ],
            ),
            NamedRouteDef.shell(
              name: 'MailRoute',
              path: '/mail',
              children: [
                NamedRouteDef(
                  name: 'InboxRoute',
                  path: '',
                  builder: (_, _) => page('InboxRoute'),
                ),
                NamedRouteDef(
                  name: 'MessageRoute',
                  path: ':id',
                  builder: (_, data) =>
                      page('Mail ${data.params.getString('id')}'),
                ),
              ],
            ),
          ],
        );
        await pumpRouterConfigApp(tester, router.config());
        unawaited(router.navigatePath('/mail/77'));
        await tester.pumpAndSettle();
        await expectBrowserUrl('/mail/77');

        await expectBrowserEntryAfter(-1, () async {
          pressBrowserBack();
          await pumpUntilFound(tester, find.text('FeedRoute'));
          await tester.pumpAndSettle();
        });

        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        await expectBrowserUrl('/');

        await expectBrowserEntryAfter(1, () async {
          pressBrowserForward();
          await pumpUntilFound(tester, find.text('Mail 77'));
          await tester.pumpAndSettle();
        });

        await expectBrowserUrl('/mail/77');
      },
      skip: !kIsWeb,
    );
  });
}
