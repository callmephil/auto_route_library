import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Two navigate calls to a page that is open ended with two pages of one key
// on the stack when the first call waited on its guard. Flutter's Navigator
// fails its check for duplicate page keys in a debug build, and a release
// build shows the earlier page over the later one.
// Setup: the path of MessageRoute takes the id of a message. Its guard
// waits before it answers for message 13 and lets the others in at once.
// Steps: message 42 is open. Call navigate to message 13 and, while its
// guard waits, navigate to message 14, which opens in the place of 42. Then
// the guard of 13 answers.
// Was: two message pages, 14 and over it 13, both with the match id of the
// page that showed 42. Each navigation had picked that page to reach again
// before its guard was asked.
// Should: one message page. It shows message 13 when the guard lets it in
// and stays on message 14 when the guard rejects. The answer that comes
// last decides.
// Native behavior this holds to: Flutter's Navigator requires every page of
// its list to have its own key, and a page that takes the place of one with
// the same type and key updates that page's route. On the web a navigation
// that ends later replaces the document the earlier one showed, so there
// are never two.
void main() {
  late Completer<bool> answerFor13;

  RootStackRouter buildRouter() => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Text('HomeRoute'),
      ),
      NamedRouteDef(
        name: 'MessageRoute',
        path: '/message/:id',
        guards: [
          AutoRouteGuard.simple((resolver, _) async {
            if (resolver.route.params.getString('id') != '13') {
              return resolver.next();
            }
            if (await answerFor13.future) {
              resolver.next();
            } else {
              resolver.reject();
            }
          }),
        ],
        builder: (_, data) => Text('Message ${data.params.getString('id')}'),
      ),
      NamedRouteDef(
        name: 'NotesRoute',
        path: '/notes',
        builder: (_, _) => const Text('NotesRoute'),
      ),
    ],
  );

  NamedRoute message(String id) => .new('MessageRoute', params: {'id': id});

  List<String> shown(StackRouter router) => [
    for (final page in router.stack)
      page.routeData.params.optString('id') ?? page.routeData.name,
  ];

  // Opens Home and message 42 over it, then calls navigate to message 13,
  // whose guard waits, and navigate to message 14.
  Future<RootStackRouter> openThenNavigateTwice(WidgetTester tester) async {
    // Made in the test, so its answer runs on the test's clock.
    answerFor13 = Completer();
    final router = buildRouter();
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.push(message('42')));
    await tester.pumpAndSettle();

    unawaited(router.navigate(message('13')));
    await tester.pumpAndSettle();
    unawaited(router.navigate(message('14')));
    await tester.pumpAndSettle();

    expect(shown(router), ['HomeRoute', '14']);
    return router;
  }

  testWidgets('The navigation whose guard answers later shows its page in '
      'the one page', (tester) async {
    final router = await openThenNavigateTwice(tester);

    answerFor13.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shown(router), ['HomeRoute', '13']);
    expect(find.text('Message 13'), findsOneWidget);
    expect(find.text('Message 14'), findsNothing);
    expect(router.currentUrl, '/message/13');
  });

  testWidgets('A navigation whose guard rejects later leaves the page of '
      'the other', (tester) async {
    final router = await openThenNavigateTwice(tester);

    answerFor13.complete(false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shown(router), ['HomeRoute', '14']);
    expect(find.text('Message 14'), findsOneWidget);
    expect(router.currentUrl, '/message/14');
  });

  // Steps: as above, then push Notes over message 14 before the guard of 13
  // answers.
  // Should: a page pushed meanwhile stays, as it does over any navigation
  // that waits, and message 13 takes the one message page.
  testWidgets('A page pushed meanwhile stays, and there is still one page '
      'of the route', (tester) async {
    final router = await openThenNavigateTwice(tester);
    unawaited(router.push(const NamedRoute('NotesRoute')));
    await tester.pumpAndSettle();

    answerFor13.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(shown(router), ['HomeRoute', 'NotesRoute', '13']);
    expect(find.text('Message 13'), findsOneWidget);
  });
}
