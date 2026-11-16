import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A link into a page that is not open yet, to a child whose guard takes its
// time, left the page's nested router showing nothing while the guard
// decided, although the page the link brings below its own was on that
// router's stack already.
// Setup: MailRoute at '/mail' holds a nested router with InboxRoute ('') and
// MessageRoute (':id'), whose guard waits for an answer. A link brings the
// pages below its own, here the inbox, as it does off the web.
// Steps: the app shows Home. The platform hands it '/mail/20'. Then the
// guard answers.
// Was: while the guard decided, Mail showed its placeholder, though its
// router held the inbox, whose navigator nobody had told.
// Should: the inbox shows while the guard decides. Then the message opens
// over it, or, when the guard rejects, Mail is taken back and Home shows.
// Native behavior this holds to: Flutter's Navigator shows the pages its
// list holds. On Android a link puts the start destination under the linked
// screen, and it is on screen until the linked screen is.
void main() {
  late Completer<bool> answer;

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
        builder: (_, _) => Scaffold(
          body: AutoRouter(placeholder: (_) => const Text('Loading mail')),
        ),
        children: [
          NamedRouteDef(
            name: 'InboxRoute',
            path: '',
            builder: (_, _) => const Text('InboxRoute'),
          ),
          NamedRouteDef(
            name: 'MessageRoute',
            path: ':id',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                if (await answer.future) {
                  resolver.next();
                } else {
                  resolver.reject();
                }
              }),
            ],
            builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
          ),
        ],
      ),
    ],
  );

  List<String> mailPages(RootStackRouter router) => [
    ...?router
        .innerRouterOf<StackRouter>('MailRoute')
        ?.stack
        .map((page) => page.routeData.name),
  ];

  // Shows Home, then hands the app the link to message 20, with the inbox
  // below it. The guard of the message has not answered yet.
  Future<RootStackRouter> openLink(WidgetTester tester) async {
    // Made in the test, so its answer runs on the test's clock.
    answer = Completer();
    final router = buildRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: true),
    );
    await tester.binding.handlePushRoute('/mail/20');
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('The page a link brings below its own shows while the guard of '
      "the link's page decides", (tester) async {
    final router = await openLink(tester);

    expect(mailPages(router), ['InboxRoute']);
    expect(find.text('InboxRoute'), findsOneWidget);
    expect(find.text('Loading mail'), findsNothing);

    answer.complete(true);
    await tester.pumpAndSettle();

    expect(mailPages(router), ['InboxRoute', 'MessageRoute']);
    expect(find.text('Mail 20'), findsOneWidget);
    expect(router.currentUrl, '/mail/20');
  });

  // A "no" takes Mail back, with the inbox in it: a refused navigation
  // changes nothing, as Android's conditional navigation pops back from a
  // destination whose check fails.
  testWidgets('Mail is taken back when the guard then rejects', (tester) async {
    final router = await openLink(tester);
    final shownMeanwhile = find.text('InboxRoute').evaluate().length;

    answer.complete(false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shownMeanwhile, 1);
    expect(router.stack.map((page) => page.routeData.name), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(router.currentUrl, '/');
  });

  // A path the app calls names the message alone, so the nested router has
  // no page on its stack while the guard decides. It shows its placeholder,
  // which is what the placeholder is for, and not its first page: that page
  // would have to leave again once the guard lets the message in, or the
  // pages would depend on how long the guard took.
  // Should: the placeholder meanwhile, then the message as the only page.
  testWidgets('A router named one page alone shows its placeholder while '
      "that page's guard decides", (tester) async {
    answer = Completer();
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());

    unawaited(router.navigatePath('/mail/20'));
    await tester.pumpAndSettle();

    expect(mailPages(router), isEmpty);
    expect(find.text('Loading mail'), findsOneWidget);

    answer.complete(true);
    await tester.pumpAndSettle();

    expect(mailPages(router), ['MessageRoute']);
    expect(find.text('Mail 20'), findsOneWidget);
    expect(find.text('Loading mail'), findsNothing);
  });
}
