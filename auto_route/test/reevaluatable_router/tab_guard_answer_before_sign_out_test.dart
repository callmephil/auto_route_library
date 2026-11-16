import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab change whose guard said yes from before a sign-out showed the tab
// for a moment. A lead of the audit of auto_route/lib (G5 of plan 3), on dev
// 921fce58.
// Setup: tabs Feed, Profile and Account, Profile behind a guard that reads
// the session, awaits a request and then answers from what it read, as a
// guard that sends the token it read does. The session is the router's
// reevaluateListenable.
// Steps: on Feed, the user chooses Profile (setActiveIndex, navigate or
// navigatePath). While its guard waits, the session ends, in the same turn
// or a frame later. Then the request completes and the guard says yes.
// Was: the stale yes was taken: the tabs switched to Profile, built its
// page offstage for the signed-out user (its initState, say a fetch of
// private data, ran), and the url went to /profile; the reevaluation then
// asked the guard again and switched back to Feed in the same turn. Tab
// listeners heard [1, 0] and the url /profile then /feed. A page of a stack
// already drops such an answer (_canNavigate, a05b2755); the tabs did not.
// Should: the stale yes is dropped and the guard is asked again before the
// tab shows; it then rejects, so the tabs stay on Feed: the listeners and
// the url hear no tab change, and Profile's page is never built.
// Native behavior this holds to: Flutter's Router drops the answer of an
// older route parse once newer route information has arrived
// (`_processParsedRouteInformation`, router.dart), so only the last change
// is applied.
void main() {
  late ValueNotifier<bool> isSignedIn;
  late List<Completer<void>> requests;
  late List<String> asked;
  late Map<String, int> built;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    requests = [];
    asked = [];
    built = {};
  });

  // Reads the session, waits for its request when there is one, and answers
  // from what it read.
  final sessionGuard = AutoRouteGuard.simple((resolver, _) async {
    asked.add(resolver.routeName);
    final wasSignedIn = isSignedIn.value;
    if (requests.isNotEmpty) await requests.removeAt(0).future;
    wasSignedIn ? resolver.next() : resolver.reject();
  });

  NamedRouteDef plain(String name, String path, {AutoRouteGuard? guard}) =>
      .new(
        name: name,
        path: path,
        guards: [?guard],
        builder: (_, _) {
          built.update(name, (n) => n + 1, ifAbsent: () => 1);
          return Center(child: Text(name));
        },
      );

  RootStackRouter buildRouter() => .build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(
          body: AutoTabsRouter(
            routes: [
              NamedRoute('FeedTab'),
              NamedRoute('ProfileTab'),
              NamedRoute('AccountTab'),
            ],
          ),
        ),
        children: [
          plain('FeedTab', 'feed'),
          plain('ProfileTab', 'profile', guard: sessionGuard),
          plain('AccountTab', 'account'),
        ],
      ),
    ],
  );

  final tabChanges = <String, void Function(RootStackRouter, TabsRouter)>{
    'setActiveIndex': (_, tabs) => tabs.setActiveIndex(1),
    'navigate': (router, _) => unawaited(
      router.navigate(
        const NamedRoute('HomeRoute', children: [NamedRoute('ProfileTab')]),
      ),
    ),
    'navigatePath': (router, _) => unawaited(router.navigatePath('/profile')),
  };

  for (final MapEntry(key: how, value: change) in tabChanges.entries) {
    for (final isFrameApart in [true, false]) {
      final moment = isFrameApart ? 'a frame after' : 'in the same turn as';
      testWidgets('A sign-out $moment a tab change by $how whose guard waits '
          "drops the guard's yes and asks it again", (tester) async {
        final router = buildRouter();
        await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
        final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
        final request = Completer<void>();
        requests.add(request);
        final indexes = <int>[];
        void hearIndex() => indexes.add(tabs.activeIndex);
        tabs.addListener(hearIndex);
        addTearDown(() => tabs.removeListener(hearIndex));
        final urls = <String>[];
        void hearUrl() => urls.add(router.urlState.url);
        router.addListener(hearUrl);
        addTearDown(() => router.removeListener(hearUrl));

        change(router, tabs);
        if (isFrameApart) await tester.pump();
        isSignedIn.value = false;
        await tester.pump();
        request.complete();
        final seen = <int>[];
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          seen.add(find.text('ProfileTab').evaluate().length);
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(seen, everyElement(0));
        expect(asked, ['ProfileTab', 'ProfileTab']);
        expect(tabs.activeIndex, 0);
        expect(router.urlState.url, '/feed');
        expect(indexes, isNot(contains(1)));
        expect(urls, isNot(contains('/profile')));
        expect(built, isNot(contains('ProfileTab')));
      });
    }
  }

  // Passes before the fix too.
  testWidgets("A sign-out and a sign-in again during the guard's wait show "
      'the tab once the guard, asked again, says yes', (tester) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
    final request = Completer<void>();
    requests.add(request);
    final indexes = <int>[];
    void hearIndex() => indexes.add(tabs.activeIndex);
    tabs.addListener(hearIndex);
    addTearDown(() => tabs.removeListener(hearIndex));

    tabs.setActiveIndex(1);
    await tester.pump();
    isSignedIn.value = false;
    await tester.pump();
    isSignedIn.value = true;
    await tester.pump();
    request.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Asked again for the stale yes, and by the reevaluations of the two
    // changes, which find the tab shown.
    expect(asked, everyElement('ProfileTab'));
    expect(tabs.activeIndex, 1);
    // Shown once, and kept.
    expect(indexes.skipWhile((index) => index != 1), everyElement(1));
    expect(router.urlState.url, '/profile');
    expect(find.text('ProfileTab'), findsOneWidget);
  });
}
