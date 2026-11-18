import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// callmephil/auto_route_library#9: off the web, the url of the running app
// named a link's page while the link's guard decided.
// Setup: Home at '/', and Secret at '/secret', whose guard waits for the
// test's answer.
// Steps: the platform hands the running app the link '/secret'. The guard
// waits, then says yes or no.
// Was: while the guard waited, Home showed, but currentUrl and urlState
// named '/secret'. After a no, the url went back to '/'.
// Should: while the guard waits, the url names Home. After a yes, it names
// Secret from the frame that shows Secret. After a no, it never changed.
// Off the web only: on the web the browser shows the url of a link at once,
// in its address bar.
// Native behavior this holds to: Android's NavController names the
// destination on top of its back stack as currentDestination, and a
// navigation that does not happen changes nothing. Flutter's Navigator tells
// its observers of a new route only once the route is in its history.
void main() {
  late Completer<bool> answer;

  RootStackRouter router() => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Text('Home'),
      ),
      NamedRouteDef(
        name: 'SecretRoute',
        path: '/secret',
        guards: [
          AutoRouteGuard.simple((resolver, _) async {
            (await answer.future) ? resolver.next() : resolver.reject();
          }),
        ],
        builder: (_, _) => const Text('Secret'),
      ),
    ],
  );

  for (final isYes in [false, true]) {
    testWidgets(
      'A link whose guard says ${isYes ? 'yes' : 'no'}: the url names the '
      'page on screen',
      (tester) async {
        answer = Completer<bool>();
        final r = router();
        final config = r.config();
        await pumpRouterConfigApp(tester, config);
        final delegate = config.routerDelegate as AutoRouterDelegate;
        // Each url the app reports, with whether Secret was on screen.
        final urls = <(String, bool)>[];
        void record() =>
            urls.add((r.currentUrl, find.text('Secret').evaluate().isNotEmpty));
        r.addListener(record);
        r.navigationHistory.addListener(record);
        addTearDown(() {
          r.removeListener(record);
          r.navigationHistory.removeListener(record);
        });

        unawaited(tester.binding.handlePushRoute('/secret'));
        await tester.pump();
        await tester.pump();

        expect(find.text('Home'), findsOneWidget);
        expect(r.currentUrl, '/');
        expect(r.urlState.url, '/');
        expect(delegate.urlState.url, '/');
        expect(delegate.currentConfiguration?.url, '/');

        answer.complete(isYes);
        // The first frame that shows Secret.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (find.text('Secret').evaluate().isNotEmpty) break;
        }
        if (isYes) {
          expect(find.text('Secret'), findsOneWidget);
          expect(r.currentUrl, '/secret');
          expect(delegate.currentConfiguration?.url, '/secret');
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(r.currentUrl, isYes ? '/secret' : '/');
        expect(r.urlState.url, isYes ? '/secret' : '/');
        if (!isYes) {
          expect(urls.map((url) => url.$1), everyElement('/'));
        }
      },
      skip: kIsWeb,
    );
  }
}
