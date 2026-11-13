import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the second audit of auto_route/lib (L2-3, its first cause); on
// dev too, no upstream issue.
// Of two links into a nested router, the one handed over first ended on top
// when its guard answered later, as a second page with the key of the page
// the later link opened: the Navigator's check for duplicate page keys
// failed. A navigation a link starts gives up once a later link has been let
// in, but the batch of a nested router, which starts after the root's part
// of the link, did not know its link. It now reads its link from the zone
// the link's navigation runs in, and each link keeps its own accepted step.
// Steps: the app shows message 42 in the nested router of Mail. The platform
// hands it /mail/13, whose guard awaits a request, then /mail/14, which
// opens, or /mail/99, whose guard rejects it. The guard of 13 then lets it
// in.
// Native behavior this holds to: of two links, the one handed over last is
// on screen, as Flutter's Router drops a route whose parse ends after a newer
// one was reported (_processParsedRouteInformation); a link that is refused
// changes nothing, so the one before it still opens. Flutter's Navigator
// requires every page to have its own key.
void main() {
  Completer<bool>? slowAnswer;

  RootStackRouter build() => .build(
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
        children: [
          NamedRouteDef(
            name: 'MessageRoute',
            path: ':id',
            guards: [
              AutoRouteGuard.simple((resolver, _) async {
                switch (resolver.route.params.getString('id')) {
                  case '99':
                    return resolver.reject();
                  case '13':
                    final answer = slowAnswer = Completer<bool>();
                    return await answer.future
                        ? resolver.next()
                        : resolver.reject();
                }
                resolver.next();
              }),
            ],
            builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
          ),
        ],
      ),
    ],
  );

  setUp(() => slowAnswer = null);

  Future<RootStackRouter> openMessage42(WidgetTester tester) async {
    final router = build();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.navigatePath('/mail/42'));
    await tester.pumpAndSettle();
    expect(find.text('Mail 42'), findsOneWidget);
    return router;
  }

  List<String?> ids(RootStackRouter router) => [
    for (final page in router.innerRouterOf<StackRouter>('MailRoute')!.stack)
      page.routeData.params.optString('id'),
  ];

  testWidgets('Of two links into a nested router, the one handed over last '
      'stays on screen when the guard of the first answers later', (
    tester,
  ) async {
    final router = await openMessage42(tester);

    await tester.binding.handlePushRoute('/mail/13');
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('/mail/14');
    await tester.pumpAndSettle();
    final shownBefore = ids(router);
    expect(shownBefore, ['14']);

    slowAnswer!.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(ids(router), shownBefore);
    expect(find.text('Mail 14'), findsOneWidget);
    expect(router.currentUrl, '/mail/14');
  });

  testWidgets('A later link into the nested router that its guard rejects '
      'leaves the first to open once its guard answers', (tester) async {
    final router = await openMessage42(tester);

    await tester.binding.handlePushRoute('/mail/13');
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('/mail/99');
    await tester.pumpAndSettle();
    expect(find.text('Mail 42'), findsOneWidget);

    slowAnswer!.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(ids(router), ['13']);
    expect(find.text('Mail 13'), findsOneWidget);
    expect(router.currentUrl, '/mail/13');
  });
}
