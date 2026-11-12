import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// replacePath() rejected by a guard dropped the page it would replace.
// Found in the fork while fixing a batch a later guard rejects; replace() had
// the same bug (#2046).
// Open Home, push First, then replacePath('/second'), whose guard rejects it.
// replacePath() took First off the stack before the guards ran, and nothing
// put it back: the stack was [Home] while First stayed on screen at /first,
// the code that pushed First was told it had closed, and the next push took
// First off the screen. A redirect showed over Home, and canceling it showed
// Home instead of First.
// Native behavior this holds to: a replace navigation the web's navigate
// event cancels aborts before the url or the current entry changes (HTML,
// "inner navigate event firing algorithm"); Flutter's
// Navigator.pushReplacement takes the old route off in the same step that
// pushes the new one; Android's FragmentTransaction.replace() runs in one
// atomic transaction; and on iOS a segue that shouldPerformSegue stops is
// ignored. So a rejected replacePath leaves the stack, the url and the wait of
// the code that opened the page as they were; an accepted one swaps the top
// page.
void main() {
  late RootStackRouter router;
  late bool isAllowed;
  late bool isRedirecting;
  Completer<bool>? decision;
  NavigationResolver? redirected;

  Widget page(String name) => Scaffold(body: Center(child: Text(name)));

  NamedRouteDef plainRoute(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => page(name));

  setUp(() {
    isAllowed = false;
    isRedirecting = false;
    decision = null;
    redirected = null;
    router = RootStackRouter.build(
      routes: [
        plainRoute('HomeRoute', '/'),
        plainRoute('FirstRoute', '/first'),
        plainRoute('ThirdRoute', '/third'),
        plainRoute('LoginRoute', '/login'),
        NamedRouteDef(
          name: 'SecondRoute',
          path: '/second',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              if (isRedirecting) {
                redirected = resolver;
                unawaited(
                  resolver.redirectUntil(const NamedRoute('LoginRoute')),
                );
                return;
              }
              final isLetThrough = await decision?.future ?? isAllowed;
              if (isLetThrough) {
                resolver.next();
              } else {
                resolver.reject();
              }
            }),
          ],
          builder: (_, _) => page('SecondRoute'),
        ),
      ],
    );
  });

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  // Opens Home, pushes First and returns whether the code that pushed First
  // has been told it closed.
  Future<bool Function()> openFirst(WidgetTester tester) async {
    await pumpRouterConfigApp(tester, router.config());
    var isFirstClosed = false;
    unawaited(
      router
          .push(const NamedRoute('FirstRoute'))
          .then((_) => isFirstClosed = true),
    );
    await tester.pumpAndSettle();
    return () => isFirstClosed;
  }

  testWidgets(
    'A replacePath rejected by a guard keeps the page it would replace',
    (tester) async {
      final isFirstClosed = await openFirst(tester);

      unawaited(router.replacePath('/second'));
      await tester.pumpAndSettle();

      expect(stackNames(), ['HomeRoute', 'FirstRoute']);
      expectTopPage(router, 'FirstRoute');
      expect(router.navigationHistory.isUrlStateMarkedForReplace, isFalse);
      expect(isFirstClosed(), isFalse);
      final urlAfterReject = router.currentUrl;

      // The next change of the stack keeps First under the new page.
      unawaited(router.push(const NamedRoute('ThirdRoute')));
      await tester.pumpAndSettle();
      expect(stackNames(), ['HomeRoute', 'FirstRoute', 'ThirdRoute']);
      await router.maybePop();
      await tester.pumpAndSettle();
      expectTopPage(router, 'FirstRoute');
      expect((urlAfterReject, router.currentUrl), ('/first', '/first'));
    },
  );

  testWidgets(
    'The page a replacePath would replace stays on the stack while the guard '
    'decides',
    (tester) async {
      final isFirstClosed = await openFirst(tester);
      final pending = Completer<bool>();
      decision = pending;

      unawaited(router.replacePath('/second'));
      await tester.pump();
      final stackWhileDeciding = stackNames();

      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
        [stackWhileDeciding, stackNames()],
        [
          ['HomeRoute', 'FirstRoute'],
          ['HomeRoute', 'FirstRoute'],
        ],
      );
      expectTopPage(router, 'FirstRoute');
      expect(isFirstClosed(), isFalse);
    },
  );

  testWidgets(
    'A replacePath redirected by its guard keeps the page under the redirect, '
    'and canceling the redirect shows it again',
    (tester) async {
      isRedirecting = true;
      await openFirst(tester);

      unawaited(router.replacePath('/second'));
      await tester.pumpAndSettle();
      expect(stackNames(), ['HomeRoute', 'FirstRoute', 'LoginRoute']);

      // Leaving the redirect without passing the guard rejects the route.
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(stackNames(), ['HomeRoute', 'FirstRoute']);
      expectTopPage(router, 'FirstRoute');
      expect(router.currentUrl, '/first');
    },
  );

  testWidgets('A replacePath accepted by its guard swaps the top page', (
    tester,
  ) async {
    isAllowed = true;
    final isFirstClosed = await openFirst(tester);

    unawaited(router.replacePath('/second'));
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute', 'SecondRoute']);
    expectTopPage(router, 'SecondRoute');
    expect(router.currentUrl, '/second');
    expect(isFirstClosed(), isTrue);
  });

  testWidgets(
    'A replacePath its guard lets through after a redirect swaps the top page',
    (tester) async {
      isRedirecting = true;
      final isFirstClosed = await openFirst(tester);

      unawaited(router.replacePath('/second'));
      await tester.pumpAndSettle();
      redirected?.next();
      await tester.pumpAndSettle();

      expect(stackNames(), ['HomeRoute', 'SecondRoute']);
      expectTopPage(router, 'SecondRoute');
      expect(isFirstClosed(), isTrue);
    },
  );
}
