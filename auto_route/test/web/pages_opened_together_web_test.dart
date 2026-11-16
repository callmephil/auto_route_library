// Runs only in Chrome, `flutter test --platform chrome`: it needs the
// browser's own history.
@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'browser_history.dart';
import 'native_walk.dart';

// On the web, pages the app opens together, with pushAll, replaceAll or
// popAndPushAll, have a browser entry each, so the back button closes them
// one by one, as the system back does. Pages a link
// opens together share the link's entry: the user made one navigation, and
// the back button leaves to where they came from.
//
// Before, only the page on top had an entry: the first press of the back
// button closed every page opened with it. After a replaceAll that a guard
// rejects, which puts the pages back, the pages under the one on top had
// none.
//
// Native behavior this holds to: Flutter's Navigator, where each route
// pushed is closed by a system back of its own, whether it was pushed alone
// or with others; and on the web a link is one navigation with one entry,
// as a document a link opens has one however much it shows.
RootStackRouter _router() => .build(
  routes: [
    for (final (name, path) in [
      ('HomeRoute', '/'),
      ('ARoute', '/a'),
      ('BRoute', '/b'),
      ('CRoute', '/c'),
    ])
      NamedRouteDef(name: name, path: path, builder: (_, _) => Text(name)),
    NamedRouteDef(
      name: 'MemberRoute',
      path: '/member',
      guards: [AutoRouteGuard.simple((resolver, _) => resolver.reject())],
      builder: (_, _) => const Text('MemberRoute'),
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

const List<PageRouteInfo> _abc = [
  NamedRoute('ARoute'),
  NamedRoute('BRoute'),
  NamedRoute('CRoute'),
];

// One call that opens several pages: the pages open before it, over Home,
// and the call.
final Map<String, (List<String>, WalkCall)> _calls = {
  'pushAll of A, B and C': ([], (router) => unawaited(router.pushAll(_abc))),
  'replaceAll with B and C': (
    ['ARoute'],
    (router) => unawaited(
      router.replaceAll(const [NamedRoute('BRoute'), NamedRoute('CRoute')]),
    ),
  ),
  'popAndPushAll of B and C': (
    ['ARoute'],
    (router) => unawaited(
      router.popAndPushAll(const [NamedRoute('BRoute'), NamedRoute('CRoute')]),
    ),
  ),
  'pushAll of a page and a nested router with two pages': (
    [],
    (router) => unawaited(
      router.pushAll(const [
        NamedRoute('ARoute'),
        NamedRoute(
          'MailRoute',
          children: [
            NamedRoute('InboxRoute'),
            NamedRoute('MessageRoute', params: {'id': 5}),
          ],
        ),
      ]),
    ),
  ),
  // The guard of the new page rejects it, and the pages closed for it are
  // put back.
  'replaceAll with a page its guard rejects': (
    ['ARoute', 'BRoute'],
    (router) => unawaited(router.replaceAll(const [NamedRoute('MemberRoute')])),
  ),
};

void main() {
  useRealBrowserHistory();
  useLiveFrames();
  setUp(rewindBrowserHistory);

  // The system back's walk of each case, kept for the second run.
  final systemBack = <String, List<String>>{};

  // Steps: open the pages over Home, make the call, then press the browser's
  // back button down to the first entry and its forward button up again.
  // Each case runs once with the browser landing before the next frame and
  // once with the frame first.
  for (final MapEntry(key: name, value: (opens, call)) in _calls.entries) {
    for (final isFrameFirst in [false, true]) {
      testWidgets('On web, after $name the back button shows the pages the '
          'system back shows${isFrameFirst ? ', with the frame before the '
                    'browser lands' : ''}', (tester) async {
        await expectNativeWalk(
          tester,
          router: _router,
          opens: opens,
          calls: [call],
          isFrameFirst: isFrameFirst,
          systemBack: systemBack[name] ??= await systemBackWalk(
            tester,
            router: _router,
            opens: opens,
            calls: [call],
          ),
        );
      });
    }
  }

  // Steps: open the app at '/mail/5', a link that opens Home, the mail page
  // and, in its router, the inbox and a message.
  testWidgets('On web, the pages a link opens together share its entry', (
    tester,
  ) async {
    openBrowserAt(tester, '/mail/5');
    final router = _router();
    addTearDown(router.dispose);
    await pumpAsRunApp(
      tester,
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: (_) => const DeepLink([
            NamedRoute('HomeRoute'),
            NamedRoute(
              'MailRoute',
              children: [
                NamedRoute('InboxRoute'),
                NamedRoute('MessageRoute', params: {'id': 5}),
              ],
            ),
          ]),
        ),
      ),
    );
    await settleBrowser(tester);

    expect(router.stack.map((page) => page.name), ['HomeRoute', 'MailRoute']);
    expect(find.text('MessageRoute'), findsOneWidget);
    expect((browserSerialCount, browserPath), (0, '/mail/5'));
  });
}
