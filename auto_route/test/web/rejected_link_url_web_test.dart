@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';

// Found by an audit of auto_route/lib, with no upstream issue.
// On the web, after the browser's forward button reached an entry whose guard
// now rejects, the address bar kept the rejected page's url while the page
// before showed: the delegate set the link's url before its guards ran, and
// a rejected single route changes no page, so nothing rebuilt the url.
// Steps: the app opens Home and pushes Login. The user signs in, which makes
// Login's guard reject, then presses the browser's back and forward buttons.
// Native behavior this holds to: a browser can't cancel a traversal the app
// receives, so the app steps it back to the entry of the page it shows: as
// with a traversal canceled through the Navigation API
// (NavigateEvent.preventDefault), the browser stands where it stood, the
// address bar names what is on screen and the entries stay as they were.
// Until the web history became the browser's one writer, the url of the
// page shown was written over the rejected page's entry, which gave that
// page two entries.
void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('On web, forward to an entry its guard now rejects shows the '
      'url of the page on screen', (tester) async {
    final isSignedIn = ValueNotifier(false);
    addTearDown(isSignedIn.dispose);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
        ),
        NamedRouteDef(
          name: 'LoginRoute',
          path: '/login',
          guards: [
            AutoRouteGuard.simple(
              (resolver, _) =>
                  isSignedIn.value ? resolver.reject() : resolver.next(),
            ),
          ],
          builder: (_, _) => const Scaffold(body: Text('LoginRoute')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
    await settleBrowser(tester);
    unawaited(router.pushPath('/login'));
    await settleBrowser(tester);
    expect(browserPath, '/login');
    final loginEntry = browserSerialCount;

    isSignedIn.value = true;
    await pressBrowserBack(tester);
    expect(browserSerialCount, loginEntry - 1);
    await pressBrowserForward(tester);

    expect(find.text('HomeRoute'), findsOneWidget);
    expect(router.currentUrl, '/');
    expect((browserSerialCount, browserPath), (loginEntry - 1, '/'));
  });
}
