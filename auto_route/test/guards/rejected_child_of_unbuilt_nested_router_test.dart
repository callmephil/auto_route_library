import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A link or a path to a guarded page inside a nested router that is not
// built yet, a shell that is not open or a tab never opened, left that
// router blank when the guard rejected the page, under a url that still
// named the rejected page.
// Setup: MailRoute at '/mail' holds a nested router with InboxRoute ('') and
// MessageRoute (':id'), whose guard rejects message 13. TabsRoute at '/tabs'
// has the tabs FirstTab and MailTab; MailTab holds the same nested routes.
// Steps: the app shows Home, or FirstTab. A link, or navigatePath, to
// '/mail/13' or '/tabs/mail/13' arrives. Or the app is opened at '/mail/13'.
// Was: Mail opened with nothing in it, at '/mail/13'. With a link its nested
// router held the inbox, but its navigator was never told; with a path it
// held no page.
// Should: Mail shows its inbox, at '/mail'.
// Native behavior this holds to: on the web a navigation that is canceled
// leaves the url of the document on screen. Flutter's Navigator shows the
// pages its list holds and takes no empty list. On Android a screen that
// ignores the link it was started with shows its start destination.
void main() {
  final mailRoutes = [
    NamedRouteDef(
      name: 'InboxRoute',
      path: '',
      builder: (_, _) => const Text('InboxRoute'),
    ),
    NamedRouteDef(
      name: 'MessageRoute',
      path: ':id',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => resolver.route.params.getString('id') == '13'
              ? resolver.reject()
              : resolver.next(),
        ),
      ],
      builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
    ),
  ];

  RootStackRouter buildRouter() => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
      ),
      NamedRouteDef(
        name: 'MailRoute',
        path: '/mail',
        builder: (_, _) => const Scaffold(body: AutoRouter()),
        children: mailRoutes,
      ),
      NamedRouteDef(
        name: 'TabsRoute',
        path: '/tabs',
        builder: (_, _) => const Scaffold(
          body: AutoTabsRouter(
            routes: [NamedRoute('FirstTab'), NamedRoute('MailTab')],
          ),
        ),
        children: [
          NamedRouteDef(
            name: 'FirstTab',
            path: 'first',
            builder: (_, _) => const Text('FirstTab'),
          ),
          NamedRouteDef(
            name: 'MailTab',
            path: 'mail',
            builder: (_, _) => const AutoRouter(),
            children: mailRoutes,
          ),
        ],
      ),
    ],
  );

  List<String> stackNames(StackRouter? router) => [
    ...?router?.stack.map((page) => page.routeData.name),
  ];

  // Every way a page can be named for a nested router before it is built.
  final ways =
      <
        String,
        FutureOr<void> Function(WidgetTester, RootStackRouter, String path)
      >{
        'A link': (tester, _, path) => tester.binding.handlePushRoute(path),
        'navigatePath': (_, router, path) =>
            unawaited(router.navigatePath(path)),
      };

  for (final MapEntry(key: way, value: open) in ways.entries) {
    testWidgets('$way to a rejected page in a shell that is not open shows '
        "the shell's first page", (tester) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());

      await open(tester, router, '/mail/13');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(router), ['HomeRoute', 'MailRoute']);
      expect(stackNames(router.innerRouterOf('MailRoute')), ['InboxRoute']);
      expect(find.text('InboxRoute'), findsOneWidget);
      expect(find.text('Mail 13'), findsNothing);
      expect(router.currentUrl, '/mail');
      expect(router.isPathActive('/mail/13'), isFalse);
      // The url took the entry the rejected page's url had: one step back
      // shows Home. The headless runner in Chrome writes no entries to count.
      if (!kIsWeb) {
        expect(router.navigationHistory.length, 2);
        router.back();
        await tester.pumpAndSettle();

        expect(stackNames(router), ['HomeRoute']);
      }
    });

    testWidgets('$way to a rejected page in a tab never opened shows the '
        "tab's first page", (tester) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());
      unawaited(router.navigatePath('/tabs/first'));
      await tester.pumpAndSettle();
      final tabs = router.innerRouterOf<TabsRouter>('TabsRoute')!;

      await open(tester, router, '/tabs/mail/13');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tabs.current.name, 'MailTab');
      expect(stackNames(tabs.innerRouterOf('MailTab')), ['InboxRoute']);
      expect(find.text('InboxRoute'), findsOneWidget);
      expect(find.text('Mail 13'), findsNothing);
      expect(router.currentUrl, '/tabs/mail');
    });
  }

  // As on the web, where a link brings only its own page, so the nested
  // router is named the rejected page alone.
  testWidgets('A link that brings no page below its own shows the first '
      'page of the shell when its page is rejected', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );

    await tester.binding.handlePushRoute('/mail/13');
    await tester.pumpAndSettle();

    expect(find.text('InboxRoute'), findsOneWidget);
    expect(router.currentUrl, '/mail');
  });

  testWidgets('An app opened at a link to a rejected page in a shell shows '
      "the shell's first page", (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/mail/13';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());

    expect(stackNames(router.innerRouterOf('MailRoute')), ['InboxRoute']);
    expect(find.text('InboxRoute'), findsOneWidget);
    expect(router.currentUrl, '/mail');
  });

  // Should: a page its guard lets in opens as before, over the inbox when
  // the link brings it, which it does off the web.
  testWidgets('A link to a page its guard lets in opens that page', (
    tester,
  ) async {
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());

    await tester.binding.handlePushRoute('/mail/14');
    await tester.pumpAndSettle();

    expect(stackNames(router.innerRouterOf('MailRoute')), [
      if (!kIsWeb) 'InboxRoute',
      'MessageRoute',
    ]);
    expect(find.text('Mail 14'), findsOneWidget);
    expect(router.currentUrl, '/mail/14');
  });
}
