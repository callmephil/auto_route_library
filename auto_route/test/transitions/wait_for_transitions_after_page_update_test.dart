import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// waitForTransitions() returned at once for a page that a navigation had
// updated in place, while the page still left or came in, so the README's
// `pop(); await waitForTransitions(); showModalBottomSheet(...)` opened a
// sheet that closed at once. Found by the second audit of auto_route/lib
// (finding W2-2).
// Cause: RouteData.animation was set once, in _PageRoute.install, on the
// data of the page the route was created with. A navigation that reaches a
// screen again (navigate with new params, replace with the same route, a new
// list of AutoRouter.declarative) gives the screen a new page with new route
// data, which the navigator hands to the same route; that data's animation
// stayed null, so a pop registered no leaving animation and a page coming in
// counted as standing still.
// Setup: Home and '/book/:id', a page with a 400 ms fade.
// Steps: push book 1, open book 2 on the same screen, pop it and await
// waitForTransitions(), as the README's "Waiting for a transition to end"
// shows.
// Was: waitForTransitions() completed while book 2 was still leaving.
// Should: it completes once the page has left, as for a page never updated.
// A route's animation belongs to the Route and stays when the navigator
// updates the route with a new page (TransitionRoute.animation), and the doc
// of waitForTransitions promises "a page coming in after a push or replace,
// and a page leaving after a pop".
const _kDuration = Duration(milliseconds: 400);

PageInfo _bookPage() => .new(
  'BookRoute',
  builder: (data) => Text('Book ${data.params.getString('id')}'),
);

RootStackRouter _router({CustomRouteBuilder? customRouteBuilder}) => .build(
  routes: [
    AutoRoute(
      path: '/',
      page: PageInfo('HomeRoute', builder: (_) => const Text('Home')),
    ),
    CustomRoute(
      path: '/book/:id',
      page: _bookPage(),
      transitionsBuilder: TransitionsBuilders.fadeIn,
      duration: _kDuration,
      reverseDuration: _kDuration,
      customRouteBuilder: customRouteBuilder,
    ),
  ],
);

NamedRoute _book(String id) => .new('BookRoute', params: {'id': id});

Animation<double> _animationOf(WidgetTester tester, String text) =>
    ModalRoute.of(tester.element(find.text(text)))!.animation!;

// Runs [pop] on the page that shows [text], then checks that
// waitForTransitions() still waits halfway through the page's exit and is
// done after it.
Future<void> _expectWaitForExit(
  WidgetTester tester,
  RoutingController router,
  String text,
  Future<void> Function() pop,
) async {
  final animation = _animationOf(tester, text);
  await pop();
  final isDone = ValueNotifier(false);
  addTearDown(isDone.dispose);
  unawaited(router.waitForTransitions().then((_) => isDone.value = true));
  await tester.pump();
  await tester.pump(_kDuration ~/ 2);
  final isLeavingHalfway = animation.isAnimating;
  final isDoneHalfway = isDone.value;
  await tester.pump(_kDuration ~/ 2 + const Duration(milliseconds: 16));
  expect(
    (isLeavingHalfway, isDoneHalfway, animation.status, isDone.value),
    (true, false, AnimationStatus.dismissed, true),
  );
}

// A route the app builds itself, whose page sets its data's animation as it
// builds, also after an update (_CurrentPageChild).
Route<T> _appRoute<T>(
  BuildContext context,
  Widget child,
  AutoRoutePage<T> page,
) => PageRouteBuilder<T>(
  settings: page,
  pageBuilder: (_, _, _) => child,
  transitionsBuilder: TransitionsBuilders.fadeIn,
  transitionDuration: _kDuration,
  reverseTransitionDuration: _kDuration,
);

void main() {
  testWidgets('A pop of a page that was never updated is waited for', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_book('1')));
    await tester.pumpAndSettle();
    await _expectWaitForExit(tester, router, 'Book 1', () async {
      router.pop();
    });
  });

  testWidgets('A pop of a page that navigate updated in place is waited for', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_book('1')));
    await tester.pumpAndSettle();
    unawaited(router.navigate(_book('2')));
    await tester.pumpAndSettle();
    expect(router.stack.map((page) => page.routeData.match), ['/', '/book/2']);
    await _expectWaitForExit(tester, router, 'Book 2', () async {
      router.pop();
    });
  });

  testWidgets('A pop of a page that replace updated in place is waited for', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_book('1')));
    await tester.pumpAndSettle();
    unawaited(router.replace(_book('2')));
    await tester.pumpAndSettle();
    await _expectWaitForExit(tester, router, 'Book 2', () async {
      router.pop();
    });
  });

  // Control: a route the app builds itself was already waited for.
  testWidgets(
    'A pop of a page of a route the app builds itself, updated in place, is '
    'waited for',
    (tester) async {
      final router = _router(customRouteBuilder: _appRoute);
      await pumpRouterApp(tester, router);
      unawaited(router.push(_book('1')));
      await tester.pumpAndSettle();
      unawaited(router.navigate(_book('2')));
      await tester.pumpAndSettle();
      await _expectWaitForExit(tester, router, 'Book 2', () async {
        router.pop();
      });
    },
  );

  // The page coming in: the first frame builds book 1, a call in the next
  // frame makes it book 2.
  testWidgets('A page updated in place while it comes in is waited for', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterApp(tester, router);
    unawaited(router.push(_book('1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    unawaited(router.navigate(_book('2')));
    final isDone = ValueNotifier(false);
    addTearDown(isDone.dispose);
    unawaited(router.waitForTransitions().then((_) => isDone.value = true));
    await tester.pump();
    await tester.pump(_kDuration ~/ 2);
    final isComingInHalfway = _animationOf(tester, 'Book 2').isAnimating;
    final isDoneHalfway = isDone.value;
    await tester.pumpAndSettle();
    expect(
      (isComingInHalfway, isDoneHalfway, isDone.value),
      (true, false, true),
    );
  });

  // Steps: a host builds AutoRouter.declarative with [ListRoute, if a book is
  // chosen BookRoute(id)]. Choose book 1, then book 2: the book's screen is
  // updated in place. Back closes it.
  testWidgets(
    'A back of a declarative page that a new list updated in place is waited '
    'for',
    (tester) async {
      final chosen = ValueNotifier<String?>(null);
      addTearDown(chosen.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HostRoute',
            path: '/',
            builder: (_, _) => ValueListenableBuilder(
              valueListenable: chosen,
              builder: (_, id, _) => AutoRouter.declarative(
                routes: (_) => [
                  const NamedRoute('ListRoute'),
                  if (id != null) _book(id),
                ],
                onPopRoute: (_, _) => chosen.value = null,
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'ListRoute',
                path: '',
                builder: (_, _) => const Text('List'),
              ),
              CustomRoute(
                path: 'book/:id',
                page: _bookPage(),
                transitionsBuilder: TransitionsBuilders.fadeIn,
                duration: _kDuration,
                reverseDuration: _kDuration,
              ),
            ],
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      chosen.value = '1';
      await tester.pumpAndSettle();
      chosen.value = '2';
      await tester.pumpAndSettle();
      expect(find.text('Book 2'), findsOneWidget);
      await _expectWaitForExit(tester, router, 'Book 2', () async {
        // System back, without settling: the test pumps the exit itself.
        await tester.binding.handlePopRoute();
      });
    },
  );
}
