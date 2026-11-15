import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The code that opened a page was told the page closed when a replaceAll of
// two routes showed the login page of its second route's guard, though the
// user then canceled the login and the page came back. Found while fixing a
// batch a later guard rejects (6f12cbce). It fails on dev and was closed by
// f3db72f8, whose tests call replaceAll with one route.
// Steps: open Home, push<int> Third and wait for its result. Call
// replaceAll([HomeRoute(), SecondRoute()]), where the guard of Second sends
// the user to a login page with redirectUntil. Cancel the login. Third then
// closes with 7.
// Was: Third came back, but the push that opened it had finished with null
// as the login page went on, and 7 reached nobody.
// Should: the push still waits and gets 7. Flutter's Navigator completes a
// route's popped future only when it applies a list of pages without that
// route for good.
void main() {
  testWidgets('A page that comes back when the login page of a later route '
      'of replaceAll is canceled still answers its caller', (tester) async {
    final signingIn = <NavigationResolver>[];
    NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) =>
        .new(
          name: name,
          path: path,
          guards: [?guard],
          builder: (_, _) => Scaffold(body: Text(name)),
        );
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'SecondRoute',
          '/second',
          AutoRouteGuard.simple((resolver, _) {
            signingIn.add(resolver);
            unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
          }),
        ),
        page('ThirdRoute', '/third'),
        page('LoginRoute', '/login'),
      ],
    );
    List<String> stackNames() =>
        router.stack.map((page) => page.routeData.name).toList();
    await pumpRouterApp(tester, router);
    final answers = <int?>[];
    unawaited(
      router.push<int>(const NamedRoute('ThirdRoute')).then(answers.add),
    );
    await tester.pumpAndSettle();
    final failures = <NavigationFailure>[];
    unawaited(
      router.replaceAll([
        const NamedRoute('HomeRoute'),
        const NamedRoute('SecondRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    final atLogin = (stackNames().join(' '), answers.length);

    signingIn.singleOrNull?.reject();
    await tester.pumpAndSettle();
    final afterCancel = (stackNames().join(' '), answers.length);
    unawaited(router.maybePop(7));
    await tester.pumpAndSettle();

    expect(atLogin, ('LoginRoute', 0));
    expect(afterCancel, ('HomeRoute ThirdRoute', 0));
    expect(stackNames(), ['HomeRoute']);
    expect(answers, [7]);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });
}
