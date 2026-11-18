import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

void main() {
  // https://github.com/callmephil/auto_route_library/issues/14
  // The app called navigatePath to a page that the tabs list of a nested
  // AutoTabsRouter does not hold, in a tab that was never opened. The router
  // opened that tab on its first page and changed the url, and onFailure got
  // no failure. The same call after the tab opened once changed nothing.
  // Steps: HomeRoute holds tabs FeedTab and MailTab. The tabs list of MailTab
  // holds InboxTab and SentTab, not DraftsTab. Start on FeedTab and do not
  // open MailTab. Call navigatePath('/mail/drafts').
  // Native: UITabBarController selects only a view controller in its
  // viewControllers array. Android's NavController.navigate to a destination
  // that its graph does not hold throws IllegalArgumentException and changes
  // nothing.
  RootStackRouter buildRouter() => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(
          body: AutoTabsRouter(
            routes: [NamedRoute('FeedTab'), NamedRoute('MailTab')],
          ),
        ),
        children: [
          NamedRouteDef(
            name: 'FeedTab',
            path: 'feed',
            builder: (_, _) => const Text('Feed'),
          ),
          NamedRouteDef(
            name: 'MailTab',
            path: 'mail',
            builder: (_, _) => const AutoTabsRouter(
              routes: [NamedRoute('InboxTab'), NamedRoute('SentTab')],
            ),
            children: [
              NamedRouteDef(
                name: 'InboxTab',
                path: 'inbox',
                builder: (_, _) => const Text('Inbox'),
              ),
              NamedRouteDef(
                name: 'SentTab',
                path: 'sent',
                builder: (_, _) => const Text('Sent'),
              ),
              NamedRouteDef(
                name: 'DraftsTab',
                path: 'drafts',
                builder: (_, _) => const Text('Drafts'),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  testWidgets('a tab never opened: the call changes nothing, reports', (
    tester,
  ) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router);
    final entries = router.navigationHistory.length;
    final failures = <NavigationFailure>[];

    unawaited(router.navigatePath('/mail/drafts', onFailure: failures.add));
    await tester.pumpAndSettle();

    expect(failures, hasLength(1));
    expect(failures.singleOrNull, isA<RouteNotFoundFailure>());
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
    expect(router.currentUrl, '/feed');
    expect(router.navigationHistory.length, entries);
  });

  testWidgets('a tab never opened: the call throws without onFailure', (
    tester,
  ) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router);
    final entries = router.navigationHistory.length;

    // The error reaches the app as an uncaught one: nothing awaits the
    // tab's nested router.
    final errors = <Object>[];
    runZonedGuarded(
      () => unawaited(router.navigatePath('/mail/drafts')),
      (error, _) => errors.add(error),
    );
    await tester.pumpAndSettle();
    expect(errors.singleOrNull, isA<FlutterError>());

    expect(find.text('Feed'), findsOneWidget);
    expect(router.currentUrl, '/feed');
    expect(router.navigationHistory.length, entries);
  });

  testWidgets('a tab opened before gives the same result', (tester) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.navigatePath('/mail/sent'));
    await tester.pumpAndSettle();
    unawaited(router.navigatePath('/feed'));
    await tester.pumpAndSettle();
    final entries = router.navigationHistory.length;
    final failures = <NavigationFailure>[];

    unawaited(router.navigatePath('/mail/drafts', onFailure: failures.add));
    await tester.pumpAndSettle();
    // The error reaches the app as an uncaught one: nothing awaits the
    // tab's nested router.
    final errors = <Object>[];
    runZonedGuarded(
      () => unawaited(router.navigatePath('/mail/drafts')),
      (error, _) => errors.add(error),
    );
    await tester.pumpAndSettle();
    expect(errors.singleOrNull, isA<FlutterError>());

    expect(failures, hasLength(1));
    expect(failures.singleOrNull, isA<RouteNotFoundFailure>());
    expect(find.text('Feed'), findsOneWidget);
    expect(router.currentUrl, '/feed');
    expect(router.navigationHistory.length, entries);
  });
}
