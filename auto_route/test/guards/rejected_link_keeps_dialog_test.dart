import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// Found by an audit of auto_route/lib; no upstream issue.
// A link the app turns down kept closing the dialog or sheet the user had
// open, such as a draft: the delegate popped the dialogs on top before it
// asked deepLinkBuilder and the guards. They now close only once the link's
// guards let it in.
// Steps: the app runs on Home with a dialog open. The platform hands it a
// link, such as from a notification, that a guard rejects, that
// deepLinkBuilder answers with DeepLink.none, or that the app lets in. Or
// the app shows a page with a nested router or tabs, and the link goes on
// into it, to a page or tab whose own guard rejects it or lets it in.
// Native behavior this holds to: a navigation that is refused changes
// nothing. On Android an open dialog stays open when onNewIntent does nothing
// with the link (seen in a native run on an API 37 emulator, 2026-11-16); on iOS an alert or a sheet stays presented when a
// link arrives (seen in a native run on an iOS 27.2 simulator, 2026-11-16); an app that returns false from
// application(_:open:options:) keeps what it presents; on the web a canceled
// navigation keeps the document, an open <dialog> included.
void main() {
  late RootStackRouter router;
  NavigationResolver? signingIn;

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (context, _) => Scaffold(
      body: Center(
        child: TextButton(
          // On the sign-in page, signing in lets the link in; any other
          // page closes.
          onPressed: () {
            final resolver = signingIn;
            signingIn = null;
            if (resolver != null) return resolver.next();
            unawaited(context.router.maybePop());
          },
          child: Text(name),
        ),
      ),
    ),
  );

  setUp(() {
    signingIn = null;
    router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page('OtherRoute', '/other'),
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
      ],
    );
  });

  List<String> stackNames() =>
      router.stack.map((page) => page.routeData.name).toList();

  Future<void> openDialog(WidgetTester tester) async {
    showDialog<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unsaved draft'), findsOneWidget);
  }

  testWidgets('A link a guard rejects keeps the open dialog', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    await openDialog(tester);

    await tester.binding.handlePushRoute('/guarded');
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute']);
    expect(find.text('Unsaved draft'), findsOneWidget);
  });

  testWidgets('A link deepLinkBuilder ignores keeps the open dialog', (
    tester,
  ) async {
    await pumpRouterConfigApp(
      tester,
      router.config(
        deepLinkBuilder: (link) => link.initial ? link : DeepLink.none,
      ),
    );
    await openDialog(tester);

    await tester.binding.handlePushRoute('/other');
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute']);
    expect(find.text('Unsaved draft'), findsOneWidget);
  });

  testWidgets('A link the app lets in closes the open dialog', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    await openDialog(tester);

    await tester.binding.handlePushRoute('/other');
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute', 'OtherRoute']);
    expect(find.text('Unsaved draft'), findsNothing);
    expect(find.text('OtherRoute'), findsOneWidget);
  });

  // The guard sends the user to sign in first; the dialog stays under the
  // sign-in page until the link is let in, and then closes with it.
  testWidgets('A link let in after signing in closes the dialog under the '
      'sign-in page', (tester) async {
    await pumpRouterConfigApp(tester, router.config());
    await openDialog(tester);

    await tester.binding.handlePushRoute('/account');
    await tester.pumpAndSettle();
    expect(stackNames(), ['HomeRoute', 'LoginRoute']);

    await tester.tap(find.text('LoginRoute'));
    await tester.pumpAndSettle();

    expect(stackNames(), ['HomeRoute', 'AccountRoute']);
    expect(find.text('Unsaved draft'), findsNothing);
    expect(find.text('AccountRoute'), findsOneWidget);

    await tester.tap(find.text('AccountRoute'));
    await tester.pumpAndSettle();
    expect(stackNames(), ['HomeRoute']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('A link into a page already open', () {
    RootStackRouter nestedRouter() => .build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
        ),
        NamedRouteDef(
          name: 'TabsRoute',
          path: '/tabs',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute('FirstTab'),
                NamedRoute('SecondTab'),
                NamedRoute('LockedTab'),
              ],
            ),
          ),
          children: [
            for (final (name, path) in [
              ('FirstTab', 'first'),
              ('SecondTab', 'second'),
            ])
              NamedRouteDef(
                name: name,
                path: path,
                builder: (_, _) => Text(name),
              ),
            NamedRouteDef(
              name: 'LockedTab',
              path: 'locked',
              guards: [
                AutoRouteGuard.simple((resolver, _) => resolver.reject()),
              ],
              builder: (_, _) => const Text('LockedTab'),
            ),
          ],
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
                AutoRouteGuard.simple(
                  (resolver, _) => resolver.route.params.getString('id') == '13'
                      ? resolver.reject()
                      : resolver.next(),
                ),
              ],
              builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
            ),
          ],
        ),
      ],
    );

    Future<void> showDraft(WidgetTester tester, BuildContext context) async {
      showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => const AlertDialog(title: Text('Unsaved draft')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);
    }

    Future<RootStackRouter> openAt(WidgetTester tester, String path) async {
      final nested = nestedRouter();
      await pumpRouterConfigApp(tester, nested.config());
      unawaited(nested.navigatePath(path));
      await tester.pumpAndSettle();
      return nested;
    }

    testWidgets('A link to a tab its guard rejects keeps the open dialog', (
      tester,
    ) async {
      final nested = await openAt(tester, '/tabs/first');
      await showDraft(tester, nested.navigatorKey.currentContext!);

      await tester.binding.handlePushRoute('/tabs/locked');
      await tester.pumpAndSettle();

      expect(find.text('FirstTab'), findsOneWidget);
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(nested.currentUrl, '/tabs/first');
    });

    testWidgets('A link to a tab the app lets in closes the open dialog', (
      tester,
    ) async {
      final nested = await openAt(tester, '/tabs/first');
      await showDraft(tester, nested.navigatorKey.currentContext!);

      await tester.binding.handlePushRoute('/tabs/second');
      await tester.pumpAndSettle();

      expect(find.text('SecondTab'), findsOneWidget);
      expect(find.text('Unsaved draft'), findsNothing);
    });

    testWidgets('A link to a nested page its guard rejects keeps the open '
        'dialogs', (tester) async {
      final nested = await openAt(tester, '/mail/42');
      final pane = nested.innerRouterOf<StackRouter>('MailRoute')!;
      await showDraft(tester, pane.navigatorKey.currentContext!);

      await tester.binding.handlePushRoute('/mail/13');
      await tester.pumpAndSettle();

      expect(pane.stack.map((page) => page.routeData.name), ['MessageRoute']);
      expect(find.text('Mail 42'), findsOneWidget);
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(nested.currentUrl, '/mail/42');
    });

    // A dialog shown on the root navigator covers the nested router too.
    testWidgets('A link to a nested page the app lets in closes the dialog '
        'over the page that holds it', (tester) async {
      final nested = await openAt(tester, '/mail/42');
      await showDraft(tester, nested.navigatorKey.currentContext!);

      await tester.binding.handlePushRoute('/mail/13');
      await tester.pumpAndSettle();
      expect(find.text('Unsaved draft'), findsOneWidget);

      await tester.binding.handlePushRoute('/mail/7');
      await tester.pumpAndSettle();

      expect(find.text('Mail 7'), findsOneWidget);
      expect(find.text('Unsaved draft'), findsNothing);
      expect(nested.currentUrl, '/mail/7');
    });
  });
}
