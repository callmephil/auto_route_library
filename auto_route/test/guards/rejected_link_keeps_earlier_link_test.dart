import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by the second audit of auto_route/lib (L2-2); on dev too, no
// upstream issue.
// A link a guard rejected still canceled an earlier link that waited on its
// guard: every link that started opening moved the root router's link
// count, also one a guard then rejected, and a navigation a link started gave
// up at its next guard's answer once the count had moved. So Account never
// opened after the user signed in; with rebuildStackOnDeepLink, or in an app
// opened at the link with no page below it, the sign-in page then closed
// over an empty stack. A navigation now gives up only once a link that
// started after it has been let in.
// Steps: the platform hands the app /account, whose guard shows a sign-in
// page, or /slow, whose guard awaits a request. While it waits, a second link
// comes that a guard rejects. The user signs in, or the request answers.
// Native behavior this holds to: a navigation that is refused changes
// nothing. On Android an activity that ignores a link in onNewIntent keeps
// what it was doing; on iOS an app that returns false from
// application(_:open:options:) keeps what it presents and awaits; on the web
// a canceled navigation leaves the current document and what it has pending.
void main() {
  late RootStackRouter router;
  NavigationResolver? signingIn;
  Completer<bool>? slowAnswer;

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (context, _) => Scaffold(body: Center(child: Text(name))),
  );

  setUp(() {
    signingIn = null;
    slowAnswer = null;
    router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('DetailsRoute', '/details'),
        page('LoginRoute', '/login'),
        page(
          'GuardedRoute',
          '/guarded',
          guard: AutoRouteGuard.simple((resolver, _) => resolver.reject()),
        ),
        page(
          'AccountRoute',
          '/account',
          guard: AutoRouteGuard.simple((resolver, _) {
            signingIn = resolver;
            unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
          }),
        ),
        page(
          'SlowRoute',
          '/slow',
          guard: AutoRouteGuard.simple((resolver, _) async {
            final answer = slowAnswer = Completer<bool>();
            if (await answer.future) {
              resolver.next();
            } else {
              resolver.reject();
            }
          }),
        ),
      ],
    );
  });

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  // The user signs in on the sign-in page the guard of AccountRoute shows.
  Future<void> signIn(WidgetTester tester) async {
    signingIn!.next();
    signingIn = null;
    await tester.pumpAndSettle();
  }

  testWidgets('A link a guard rejects leaves the link that waits behind a '
      'sign-in page to open once the user signs in', (tester) async {
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: true),
    );

    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    final whileSigningIn = stackNames();
    expect(whileSigningIn, ['HomeRoute', 'LoginRoute']);

    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();
    expect(stackNames(), whileSigningIn);

    await signIn(tester);
    expect(stackNames(), ['HomeRoute', 'AccountRoute']);
    expect(router.currentUrl, '/account');
  });

  testWidgets('A link a guard rejects leaves the link whose guard awaits a '
      'request to open once it answers', (tester) async {
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: true),
    );

    await tester.binding.handlePushRoute('/slow');
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();
    slowAnswer!.complete(true);
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute', 'SlowRoute']);
    expect(router.currentUrl, '/slow');
  });

  testWidgets('With rebuildStackOnDeepLink, the app is not left blank', (
    tester,
  ) async {
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true, includePrefixMatches: true),
    );
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(stackNames(), ['HomeRoute', 'DetailsRoute']);

    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();
    await signIn(tester);

    expect(stackNames(), ['HomeRoute', 'AccountRoute']);
  });

  // As on the web, where a link brings only its own page.
  testWidgets('An app opened at the guarded link, with no page below it, is '
      'not left blank', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/account';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );
    expect(stackNames(), ['LoginRoute']);

    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();
    await signIn(tester);

    expect(stackNames(), ['AccountRoute']);
  });

  // A link the app ignores drops no link before it either.
  testWidgets('A link deepLinkBuilder ignores leaves the waiting link to '
      'open', (tester) async {
    await pumpRouterConfigApp(
      tester,
      router.config(
        includePrefixMatches: true,
        deepLinkBuilder: (link) =>
            link.path == '/guarded' ? DeepLink.none : link,
      ),
    );

    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();
    await signIn(tester);

    expect(stackNames(), ['HomeRoute', 'AccountRoute']);
  });
}
