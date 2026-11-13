@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../named_page.dart';
import '../router_test_utils.dart';
import 'browser_history.dart';

// A list with a detail pane: MailRoute at /mail holds a nested router that
// starts empty and shows a placeholder; MessageRoute (':id') opens a mail in
// it, at /mail/42.
// Steps: open the list, open mail 42 in the pane, press the browser's back
// button.
// Was, while a nested router kept its pages for every navigation that named
// none for it: mail 42 stayed on screen while the address bar said /mail.
// Should: the pane shows its placeholder, and the browser is on the entry of
// the list.
// Native behavior this holds to: in a browser, going back to a history entry
// shows the state of that entry's url.
// Headless test off the web: test/navigate_open_shell_no_children_test.dart
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('The browser back button on web from a mail to the list empties '
      'the detail pane', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const NamedPage('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'MailRoute',
          path: '/mail',
          builder: (_, _) => Row(
            children: [
              const Expanded(child: Text('Inbox')),
              Expanded(
                child: AutoRouter(
                  placeholder: (_) => const Text('Choose a mail'),
                ),
              ),
            ],
          ),
          children: [
            NamedRouteDef(
              name: 'MessageRoute',
              path: ':id',
              builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
            ),
          ],
        ),
      ],
    );
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    unawaited(router.push(const NamedRoute('MailRoute')));
    await settleBrowser(tester);
    final listEntry = browserSerialCount;
    final pane = router.innerRouterOf<StackRouter>('MailRoute')!;
    unawaited(
      pane.push(const NamedRoute('MessageRoute', params: {'id': '42'})),
    );
    await settleBrowser(tester);
    expect((browserPath, browserSerialCount), ('/mail/42', listEntry + 1));

    await pressBrowserBack(tester);

    expect(pane.stack, isEmpty);
    expect(find.text('Choose a mail'), findsOneWidget);
    expect(find.text('Mail 42'), findsNothing);
    expect((browserPath, browserSerialCount), ('/mail', listEntry));

    await pressBrowserBack(tester);

    expect(find.text('HomeRoute'), findsOneWidget);
    expect(browserPath, '/');
  });
}
