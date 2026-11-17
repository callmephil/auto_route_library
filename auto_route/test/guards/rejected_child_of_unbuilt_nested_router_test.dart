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
// Should: Mail shows its inbox, at '/mail'. Since the guard's "no" takes
// back a page that was not open, Home shows instead, at '/', unless Mail is
// the app's only page, as when the app starts at the link without the pages
// below it. A link, and since the app's own path waits off the screen as a
// link does, a path turned down inside a tab that is not on screen leaves
// the tab on screen as it is, and the other tab's nested router on its
// inbox.
// Native behavior this holds to: on the web a navigation that is canceled
// leaves the url of the document on screen (HTML standard, navigate event).
// An app opened at the link has loaded already, so nothing is canceled
// there: the app writes the url of the page on screen itself. In debug
// builds Flutter's Navigator reports an error for an empty list of pages. On
// Android a screen that ignores the link it was started with shows its start
// destination.
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

  // Since the guard's "no" takes back the page whose nested router asked it,
  // a refused navigation into a shell that is not open changes nothing: Home
  // shows, at its url, in its own history entry.
  for (final MapEntry(key: way, value: open) in ways.entries) {
    testWidgets('$way to a rejected page in a shell that is not open takes '
        'the shell back', (tester) async {
      final router = buildRouter();
      await pumpRouterConfigApp(tester, router.config());

      await open(tester, router, '/mail/13');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackNames(router), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(find.text('Mail 13'), findsNothing);
      expect(router.currentUrl, '/');
      expect(router.isPathActive('/mail/13'), isFalse);
      // The url took the entry the rejected page's url had. The headless
      // runner in Chrome writes no entries to count.
      if (!kIsWeb) expect(router.navigationHistory.length, 1);
    });
  }

  // Opens the tabs on FirstTab; MailTab was never opened.
  Future<(RootStackRouter, TabsRouter)> openFirstTab(
    WidgetTester tester,
  ) async {
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.navigatePath('/tabs/first'));
    await tester.pumpAndSettle();
    return (router, router.innerRouterOf<TabsRouter>('TabsRoute')!);
  }

  // A path the app calls itself into a tab never opened waits off the
  // screen for the guards of the tab's nested router, as a link does: a
  // rejection keeps the tab the user is on, and leaves the other on its
  // first page.
  testWidgets('navigatePath to a rejected page in a tab never opened keeps '
      'the tab on screen', (tester) async {
    final (router, tabs) = await openFirstTab(tester);

    unawaited(router.navigatePath('/tabs/mail/13'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tabs.current.name, 'FirstTab');
    expect(find.text('FirstTab'), findsOneWidget);
    expect(stackNames(tabs.innerRouterOf('MailTab')), ['InboxRoute']);
    expect(find.text('Mail 13', skipOffstage: false), findsNothing);
    expect(router.currentUrl, '/tabs/first');
  });

  // A link the app turns down changes nothing: the tab the user is on stays
  // on screen, with its url, as a link an Android activity ignores leaves
  // its selected tab. The tab never opened is built off the screen for the
  // link, and its nested router is left on its first page, not empty.
  // Should: FirstTab shows, at its url. Choosing the Mail tab then shows the
  // inbox.
  testWidgets('A link to a rejected page in a tab never opened keeps the '
      'tab on screen and leaves the other on its first page', (tester) async {
    final (router, tabs) = await openFirstTab(tester);

    await tester.binding.handlePushRoute('/tabs/mail/13');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tabs.current.name, 'FirstTab');
    expect(find.text('FirstTab'), findsOneWidget);
    expect(router.currentUrl, '/tabs/first');
    expect(stackNames(tabs.innerRouterOf('MailTab')), ['InboxRoute']);
    expect(find.text('Mail 13', skipOffstage: false), findsNothing);

    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(find.text('InboxRoute'), findsOneWidget);
    expect(router.currentUrl, '/tabs/mail');
  });

  // A link that brings only its own page names the nested router the
  // rejected page alone. Handed over while the launch page is all the app
  // shows, it takes that page's place, so Mail is the only page and stays,
  // on its first page. On the web, where links bring only their own page,
  // a browser opens the app at its url, so no later link takes the launch
  // page's place: Mail opens over Home, and the no takes it back.
  testWidgets('A link that brings no page below its own shows the first '
      'page of the shell when its page is rejected', (tester) async {
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );

    await tester.binding.handlePushRoute('/mail/13');
    await tester.pumpAndSettle();

    if (kIsWeb) {
      expect(stackNames(router), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(router.currentUrl, '/');
      return;
    }
    expect(find.text('InboxRoute'), findsOneWidget);
    expect(router.currentUrl, '/mail');
  });

  // The app started at the link has no page to go back to: the shell stays,
  // on its first page. With the pages a link brings below its own, as off
  // the web, Home is under it, and the shell is taken back.
  testWidgets('An app opened at a link to a rejected page in a shell shows '
      "the shell's first page, or Home below it", (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/mail/13';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());

    if (kIsWeb) {
      expect(stackNames(router.innerRouterOf('MailRoute')), ['InboxRoute']);
      expect(find.text('InboxRoute'), findsOneWidget);
      expect(router.currentUrl, '/mail');
    } else {
      expect(stackNames(router), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(router.currentUrl, '/');
    }
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
