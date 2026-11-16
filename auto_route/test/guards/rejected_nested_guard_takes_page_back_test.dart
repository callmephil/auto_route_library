import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A navigation into a page that was not open, whose nested router's guard
// then said no, still moved the user: the page went on and stayed, on its
// first page, or blank when the guarded page was its only child. A link's
// dialog was closed, and the caller waited on a page it never asked for.
// Setup: Home, at the root path, shows a dialog named Draft. Mail holds a
// nested router with Inbox as its first page and Message by id. The guard
// of Message rejects message 13 at once, and decides about message 77 only
// when the test answers. The same Mail sits one router deeper, inside an
// app shell that is open on Feed. A second Mail has the guarded Message as
// its only child.
// Steps: a link, navigatePath, navigate or pushPath goes to message 13 or
// 77. Then the guard of 77 says no or yes.
// Was: Home and Mail, with Mail on Inbox or on nothing, and a link's dialog
// gone.
// Should: a no leaves the stack, the url and the dialog as they were, and
// the caller of the page gets null. While the guard decides, the dialog is
// still open. A yes opens the message, at its url. The page stays only
// when it is the only page of the app, as when the app starts at the link.
// Native behavior this holds to: Android's conditional navigation shows the
// destination first and, when the check fails (a declined login), pops back
// to the start destination. On the web a canceled navigation
// leaves the document and the url on screen, by the HTML standard's
// navigate event. UIKit dismisses nothing because a link arrived: the
// presenting controller dismisses what it presented.
Completer<bool>? _slow;

final _guard = AutoRouteGuard.simple((resolver, _) async {
  switch (resolver.route.params.getString('id')) {
    case '13':
      return resolver.reject();
    case '77':
      final answer = _slow = Completer<bool>();
      return await answer.future ? resolver.next() : resolver.reject();
  }
  resolver.next();
});

List<NamedRouteDef> _mailChildren({required bool hasFirstPage}) => [
  if (hasFirstPage)
    NamedRouteDef(
      name: 'InboxRoute',
      path: '',
      builder: (_, _) => const Text('Inbox'),
    ),
  NamedRouteDef(
    name: 'MessageRoute',
    path: ':id',
    guards: [_guard],
    builder: (_, data) => Text('Mail ${data.params.getString('id')}'),
  ),
];

NamedRouteDef _mail({required bool hasFirstPage, String path = '/mail'}) =>
    .new(
      name: 'MailRoute',
      path: path,
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: _mailChildren(hasFirstPage: hasFirstPage),
    );

RootStackRouter _rootRouter({bool hasFirstPage = true}) => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
    ),
    _mail(hasFirstPage: hasFirstPage),
  ],
);

// The app shell at '/' is open on Feed; Mail is inside it.
RootStackRouter _shellRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'AppShellRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: AutoRouter()),
      children: [
        NamedRouteDef(
          name: 'FeedRoute',
          path: '',
          builder: (_, _) => const Text('Feed'),
        ),
        _mail(hasFirstPage: true, path: 'mail'),
      ],
    ),
  ],
);

List<String> _names(StackRouter? router) => [
  ...?router?.stack.map((page) => page.routeData.name),
];

// The dialog: on screen, open but covered, or closed.
String _dialog() {
  if (find.text('Draft').hitTestable().evaluate().isNotEmpty) return 'shown';
  if (find.text('Draft', skipOffstage: false).evaluate().isNotEmpty) {
    return 'open';
  }
  return 'closed';
}

enum _Way { link, navigatePath, navigate, pushPath }

enum _Answer { rejectsAtOnce, waitsThenNo, waitsThenYes }

// Starts [way] to message [id] of Mail; completes with what the caller of
// the page gets, for the calls that hand it.
Future<Object?>? _go(
  WidgetTester tester,
  RootStackRouter router,
  _Way way,
  String id, {
  bool isInShell = false,
}) {
  switch (way) {
    case .link:
      unawaited(tester.binding.handlePushRoute('/mail/$id'));
      return null;
    case .navigatePath:
      unawaited(router.navigatePath('/mail/$id'));
      return null;
    case .navigate:
      final mail = NamedRoute(
        'MailRoute',
        children: [
          NamedRoute('MessageRoute', params: {'id': id}),
        ],
      );
      return router.navigate(
        isInShell ? NamedRoute('AppShellRoute', children: [mail]) : mail,
      );
    case .pushPath:
      return router.pushPath('/mail/$id');
  }
}

void main() {
  setUp(() => _slow = null);

  for (final isInShell in [false, true]) {
    final where = isInShell ? 'one router deeper' : 'in the root';
    for (final way in _Way.values) {
      // pushPath from the root pushes Mail on the root, not in the shell.
      if (isInShell && way == .pushPath) continue;
      for (final answer in _Answer.values) {
        final id = answer == .rejectsAtOnce ? '13' : '77';
        testWidgets('$where, ${way.name} to message $id, ${answer.name}', (
          tester,
        ) async {
          final router = isInShell ? _shellRouter() : _rootRouter();
          await pumpRouterConfigApp(tester, router.config());
          final shell = router.innerRouterOf<StackRouter>('AppShellRoute');
          final stackOf = isInShell
              ? () => _names(shell)
              : () => _names(router);
          final before = stackOf();
          final urlBefore = router.currentUrl;
          showDialog<void>(
            context: (isInShell ? shell! : router).navigatorKey.currentContext!,
            useRootNavigator: false,
            builder: (_) => const AlertDialog(title: Text('Draft')),
          );
          await tester.pumpAndSettle();
          expect(_dialog(), 'shown');

          final caller = _go(tester, router, way, id, isInShell: isInShell);
          Object? got = #waiting;
          caller?.then((result) => got = result).ignore();
          await tester.pumpAndSettle();
          if (answer != .rejectsAtOnce) {
            expect(_slow?.isCompleted, isFalse, reason: 'the guard waits');
            // Nothing is let in yet: the dialog is still open.
            expect(_dialog(), isNot('closed'), reason: 'while it decides');
            _slow!.complete(answer == .waitsThenYes);
            await tester.pumpAndSettle();
          }

          expect(tester.takeException(), isNull);
          if (answer == .waitsThenYes) {
            expect(stackOf(), [...before, 'MailRoute']);
            expect(find.text('Mail 77'), findsOneWidget);
            expect(router.currentUrl, '/mail/77');
            return;
          }
          expect(stackOf(), before);
          if (isInShell) expect(_names(router), ['AppShellRoute']);
          expect(find.text('Draft').hitTestable(), findsOneWidget);
          expect(router.currentUrl, urlBefore);
          expect(find.text('Inbox', skipOffstage: false), findsNothing);
          if (caller != null) expect(got, isNull, reason: 'caller answered');
        });
      }
    }
  }

  // A shell whose only child is the guarded page has no first page to show
  // after a "no": it is taken back too, when the navigation took no page off.
  // After replace or replaceAll, whose pages left with their callers
  // answered before the shell's router asked, it stays and shows its
  // placeholder; see shell_placeholder_while_guard_decides_test.dart.
  for (final way in _Way.values) {
    testWidgets('A shell whose only child is the guarded page, ${way.name} '
        'to it, the slow guard says no', (tester) async {
      final router = _rootRouter(hasFirstPage: false);
      await pumpRouterConfigApp(tester, router.config());

      _go(tester, router, way, '77')?.ignore();
      await tester.pumpAndSettle();
      _slow!.complete(false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_names(router), ['HomeRoute']);
      expect(find.text('HomeRoute'), findsOneWidget);
      expect(router.currentUrl, '/');
    });
  }

  // As on the web, where a link brings only its own page. The app was
  // handed a link before, so this one doesn't take the launch page's place.
  testWidgets('A link without the pages below it, rejected, leaves Home', (
    tester,
  ) async {
    final router = _rootRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );
    await tester.binding.handlePushRoute('/');
    await tester.pumpAndSettle();

    await tester.binding.handlePushRoute('/mail/13');
    await tester.pumpAndSettle();

    expect(_names(router), ['HomeRoute']);
    expect(find.text('HomeRoute'), findsOneWidget);
    expect(router.currentUrl, '/');
  });

  // The root is never left empty: the app started at the link has no page
  // to go back to, so Mail stays, on its first page. With the pages a link
  // brings below its own, as off the web, Home is under it and shows.
  // Without them, a link handed over while the launch page is all the app
  // shows, as iOS hands over the link of a cold start, takes that page's
  // place: the app is started at the link the same way.
  testWidgets("A link that takes the launch page's place, rejected", (
    tester,
  ) async {
    final router = _rootRouter();
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: false),
    );

    await tester.binding.handlePushRoute('/mail/13');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_names(router), ['MailRoute']);
    expect(find.text('Inbox'), findsOneWidget);
    expect(router.currentUrl, '/mail');
  });

  for (final includePrefixMatches in [false, true]) {
    testWidgets('An app opened at a rejected link '
        '(includePrefixMatches: $includePrefixMatches)', (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/mail/13';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final router = _rootRouter();
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: includePrefixMatches),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      if (includePrefixMatches) {
        expect(_names(router), ['HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(router.currentUrl, '/');
      } else {
        expect(_names(router), ['MailRoute']);
        expect(_names(router.innerRouterOf('MailRoute')), ['InboxRoute']);
        expect(find.text('Inbox'), findsOneWidget);
        expect(router.currentUrl, '/mail');
      }
    });
  }

  // A second navigation while the guard decides: one that leaves Mail ends
  // it; one that reaches Mail again keeps Mail when the first is refused.
  for (final isSameTurn in [true, false]) {
    final when = isSameTurn ? 'in the same turn' : 'a frame later';
    testWidgets('navigate to Home $when, then the guard says no', (
      tester,
    ) async {
      final router = _rootRouter();
      await pumpRouterConfigApp(tester, router.config());

      unawaited(router.navigatePath('/mail/77'));
      if (!isSameTurn) await tester.pump();
      unawaited(router.navigatePath('/'));
      await tester.pumpAndSettle();
      _slow?.complete(false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_names(router), ['HomeRoute']);
      expect(router.currentUrl, '/');
    });
  }

  testWidgets('navigate to the inbox while the guard decides keeps Mail '
      'when it then says no', (tester) async {
    final router = _rootRouter();
    await pumpRouterConfigApp(tester, router.config());

    unawaited(router.navigatePath('/mail/77'));
    await tester.pumpAndSettle();
    unawaited(router.navigatePath('/mail'));
    await tester.pumpAndSettle();
    _slow!.complete(false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_names(router), ['HomeRoute', 'MailRoute']);
    expect(find.text('Inbox'), findsOneWidget);
    expect(router.currentUrl, '/mail');
  });

  // A guard that sends the user to sign in, inside Mail, instead of saying
  // no at once: canceling the sign-in takes Mail back too.
  for (final isSignedIn in [true, false]) {
    testWidgets('A guard that shows a sign-in page in Mail, which the user '
        '${isSignedIn ? 'completes' : 'cancels'}', (tester) async {
      Completer<bool>? signIn;
      final router = RootStackRouter.build(
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
                name: 'InboxRoute',
                path: '',
                builder: (_, _) => const Text('Inbox'),
              ),
              NamedRouteDef(
                name: 'SignInRoute',
                path: 'sign-in',
                builder: (_, _) => const Text('SignIn'),
              ),
              NamedRouteDef(
                name: 'MessageRoute',
                path: ':id',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    final done = signIn = Completer<bool>();
                    unawaited(
                      resolver.redirectUntil(const NamedRoute('SignInRoute')),
                    );
                    await done.future ? resolver.next() : resolver.reject();
                  }),
                ],
                builder: (_, data) =>
                    Text('Mail ${data.params.getString('id')}'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());

      unawaited(router.navigatePath('/mail/77'));
      await tester.pumpAndSettle();
      expect(find.text('SignIn'), findsOneWidget);
      signIn!.complete(isSignedIn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      if (isSignedIn) {
        expect(find.text('Mail 77'), findsOneWidget);
        expect(router.currentUrl, '/mail/77');
      } else {
        expect(_names(router), ['HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(router.currentUrl, '/');
      }
    });
  }
}
