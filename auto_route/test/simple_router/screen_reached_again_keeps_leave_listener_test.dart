import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../back_test_utils.dart';
import '../router_test_utils.dart';

// When a navigation reaches a screen the navigator already shows, a new page
// takes over the screen's route, and an AutoRouteLeaveListener in the screen
// keeps hearing the screen leave. Native navigation keeps such a screen with
// whatever listens to it: Flutter's Navigator keeps the Route of a page of
// the same type and key (Navigator._updatePages gives the kept route the new
// page), so a PopScope registered with that route keeps hearing its pops; and
// UIKit's popToViewController keeps the view controller it goes back down to,
// whose viewWillDisappear is called when it later leaves.

void main() {
  late List<RouteLeaveKind> leaves;

  Widget editorPage(RouteData<Object?> data) => AutoRouteLeaveListener(
    onLeave: leaves.add,
    child: Text(switch (data.queryParams.optString('q')) {
      final query? => 'EditorRoute q=$query',
      null => 'EditorRoute',
    }),
  );

  RootStackRouter buildRouter() => .build(
    routes: [
      AutoRoute(
        path: '/',
        page: PageInfo('HomeRoute', builder: (_) => const Text('HomeRoute')),
      ),
      AutoRoute(
        path: '/editor',
        page: PageInfo('EditorRoute', builder: editorPage),
      ),
      AutoRoute(
        path: '/preview',
        page: PageInfo(
          'PreviewRoute',
          builder: (_) => const Text('PreviewRoute'),
        ),
      ),
    ],
  );

  const editor = NamedRoute<Object?>('EditorRoute');
  const preview = NamedRoute<Object?>('PreviewRoute');
  const home = NamedRoute<Object?>('HomeRoute');

  setUp(() => leaves = []);

  Future<RootStackRouter> openEditor(WidgetTester tester) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router);
    unawaited(router.push(editor));
    await tester.pumpAndSettle();
    expectTopPage(router, 'EditorRoute');
    return router;
  }

  // Steps: push EditorRoute, whose page holds an AutoRouteLeaveListener, then
  // navigate to EditorRoute and pop.
  // Happened: since the listener came in (12.4.0), it heard nothing: it
  // stayed with the screen's first page, and the pop was reported to the
  // page that took the screen over.
  // Should: the pop is reported, once.
  testWidgets('A pop of a screen navigate reached again is heard', (
    tester,
  ) async {
    final router = await openEditor(tester);
    unawaited(router.navigate(editor));
    await tester.pumpAndSettle();
    expect(leaves, isEmpty);

    router.pop();
    await tester.pumpAndSettle();
    expectTopPage(router, 'HomeRoute');
    expect(leaves, [RouteLeaveKind.popped]);
  });

  // Steps: push EditorRoute, open a link to /editor?q=1, which shows the
  // screen with the new query param, then replace it with PreviewRoute.
  // Happened: the listener heard nothing.
  // Should: the replace is reported.
  testWidgets('A replace of a screen a link reached again is heard', (
    tester,
  ) async {
    final router = await openEditor(tester);
    unawaited(router.navigatePath('/editor?q=1'));
    await tester.pumpAndSettle();
    expect(find.text('EditorRoute q=1'), findsOneWidget);
    expect(leaves, isEmpty);

    unawaited(router.replace(preview));
    await tester.pumpAndSettle();
    expectTopPage(router, 'PreviewRoute');
    expect(leaves, [RouteLeaveKind.replaced]);
  });

  // Steps: push EditorRoute and PreviewRoute over it, navigate back down to
  // EditorRoute, then press system back.
  // Happened: the listener heard the push of PreviewRoute, then nothing.
  // Should: it hears the push, then the back.
  testWidgets('A back from a screen navigated back down to is heard', (
    tester,
  ) async {
    final router = await openEditor(tester);
    unawaited(router.push(preview));
    await tester.pumpAndSettle();
    expect(leaves, [RouteLeaveKind.covered]);

    unawaited(router.navigate(editor));
    await tester.pumpAndSettle();
    expectTopPage(router, 'EditorRoute');

    await systemBack(tester);
    expectTopPage(router, 'HomeRoute');
    expect(leaves, [RouteLeaveKind.covered, RouteLeaveKind.popped]);
  });

  // Steps: push EditorRoute, then navigate to EditorRoute and, in the same
  // turn before a frame, push PreviewRoute, as an app opening a page from a
  // notification does.
  // Happened: the listener heard nothing.
  // Should: it hears the push, though the navigator hasn't shown the page
  // that took the screen over yet.
  testWidgets(
    'A push right after a navigation reaches the screen again is heard',
    (tester) async {
      final router = await openEditor(tester);
      unawaited(router.navigate(editor));
      unawaited(router.push(preview));
      await tester.pumpAndSettle();
      expectTopPage(router, 'PreviewRoute');
      expect(leaves, [RouteLeaveKind.covered]);
    },
  );

  // Steps: push EditorRoute, then replace it with EditorRoute, which keeps
  // the screen, then pop.
  // Happened: the listener heard nothing.
  // Should: the pop is reported.
  testWidgets('A pop of a screen replace kept is heard', (tester) async {
    final router = await openEditor(tester);
    unawaited(router.replace(editor));
    await tester.pumpAndSettle();
    expect(leaves, isEmpty);

    router.pop();
    await tester.pumpAndSettle();
    expectTopPage(router, 'HomeRoute');
    expect(leaves, [RouteLeaveKind.popped]);
  });

  // Steps: push EditorRoute, then replaceAll with HomeRoute and
  // EditorRoute, which keeps the editor's screen, then pop.
  // Happened: the listener heard nothing.
  // Should: the pop is reported.
  testWidgets('A pop of a screen replaceAll kept is heard', (tester) async {
    final router = await openEditor(tester);
    unawaited(router.replaceAll([home, editor]));
    await tester.pumpAndSettle();
    expect(leaves, isEmpty);

    router.pop();
    await tester.pumpAndSettle();
    expectTopPage(router, 'HomeRoute');
    expect(leaves, [RouteLeaveKind.popped]);
  });

  // Steps: an AutoRouter.declarative lists HomeRoute and EditorRoute, the
  // app adds PreviewRoute to its list, then system back twice, each of which
  // the app answers by taking the top route off its list.
  // Happened: the listener heard nothing: each new list builds new pages
  // and the navigator keeps the editor's route for the new one.
  // Should: the back that pops the editor is reported. A declarative router
  // reports only pops, so the push of PreviewRoute isn't.
  testWidgets('A back from a screen a declarative list kept is heard', (
    tester,
  ) async {
    final depth = ValueNotifier(2);
    addTearDown(depth.dispose);
    final router = RootStackRouter.build(
      routes: [
        AutoRoute(
          path: '/',
          page: PageInfo(
            'HostRoute',
            builder: (_) => ValueListenableBuilder<int>(
              valueListenable: depth,
              builder: (_, value, _) => AutoRouter.declarative(
                routes: (_) => [
                  home,
                  if (value > 1) editor,
                  if (value > 2) preview,
                ],
                onPopRoute: (_, _) => depth.value--,
              ),
            ),
          ),
          children: [
            AutoRoute(
              path: '',
              page: PageInfo(
                'HomeRoute',
                builder: (_) => const Text('HomeRoute'),
              ),
            ),
            AutoRoute(
              path: 'editor',
              page: PageInfo('EditorRoute', builder: editorPage),
            ),
            AutoRoute(
              path: 'preview',
              page: PageInfo(
                'PreviewRoute',
                builder: (_) => const Text('PreviewRoute'),
              ),
            ),
          ],
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    depth.value = 3;
    await tester.pumpAndSettle();
    expect(find.text('PreviewRoute'), findsOneWidget);

    await systemBack(tester);
    expect(find.text('EditorRoute'), findsOneWidget);
    expect(leaves, isEmpty);

    await systemBack(tester);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(leaves, [RouteLeaveKind.popped]);
  });
}
