import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A page whose guard, asked again, returned without an answer left the
// stack but stayed on screen. Item D4 of the plan-3 audit of the library,
// on dev 921fce58. Phil's decision 4 of 2026-11-16 sets what it does.
// Setup: Home, Notes and Account, each opened with push, Account's awaited
// by the code that opened it. Account's guard lets a signed-in user through
// and otherwise returns without an answer and answers later from a
// callback, as one that asks the session to sign the user in again does.
// The session is the router's reevaluateListenable.
// Steps: the session ends while Account shows. Then the user or the app
// does a pop, a push, a replace or a rebuild, and the guard says yes or no.
// Was: the stack held Home and Notes while Account still showed, with its
// url /account. A pop closed Account on screen and left the url at /account
// until the guard answered. A push from Account disposed its screen, and a
// replace replaced Notes, the page under the one on screen, and a later yes
// put Account back under the new page. The page was taken off the stack
// without the navigator being told, so the screen changed only at the next
// rebuild.
// Should (decision 4): the page leaves the stack and the screen at once,
// with the pages above it, and the url names the page shown. Its caller
// keeps waiting. A later yes puts it back on top of the stack as it then
// is, as a page whose guard lets it through goes on. A later no answers its
// caller null. pop, push and replace act on the page shown meanwhile. A
// guard that wants its page kept while it decides awaits its answer inside
// its call.
// Native behavior this holds to: Flutter's Navigator shows the pages it was
// last given (`_updatePages`, navigator.dart), so the stack and the screen
// agree. On Android a finished activity is popped from the back stack and
// destroyed, and back acts on the one shown (developer.android.com/guide/components/
// activities/tasks-and-back-stack), and the screen a sign-in callback later
// opens goes on top of the task. On the web the address bar names the page
// shown.
void Function({required bool isLetIn})? _answer;

// Lets its page in while signed in. Otherwise returns without an answer and
// answers from the callback the test calls.
AutoRouteGuard _sessionGuard(ValueNotifier<bool> isSignedIn) =>
    .simple((resolver, _) {
      if (isSignedIn.value) return resolver.next();
      _answer = ({required isLetIn}) =>
          isLetIn ? resolver.next() : resolver.reject();
    });

enum _Meanwhile { nothing, pop, systemBack, push, replace, rebuild }

void main() {
  late ValueNotifier<bool> isSignedIn;
  late List<String> accountHeard;

  setUp(() {
    isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    _answer = null;
    accountHeard = [];
  });

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(
      appBar: AppBar(leading: const AutoLeadingButton()),
      body: name == 'AccountRoute'
          ? AutoRouteLeaveListener(
              onLeave: (kind) => accountHeard.add(kind.name),
              child: Text(name),
            )
          : Text(name),
    ),
  );

  RootStackRouter buildRouter() => .build(
    routes: [
      page('HomeRoute', '/'),
      page('NotesRoute', '/notes'),
      page('AccountRoute', '/account', guard: _sessionGuard(isSignedIn)),
      page('DetailsRoute', '/details'),
      page('OtherRoute', '/other'),
    ],
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  final paths = {
    'HomeRoute': '/',
    'NotesRoute': '/notes',
    'AccountRoute': '/account',
    'DetailsRoute': '/details',
    'OtherRoute': '/other',
  };

  // The stack, the pages a tap reaches, the url and what the callers heard.
  String state(RootStackRouter router, [List<String?> answers = const []]) {
    final shown = [
      for (final name in paths.keys)
        if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
    ];
    return '${names(router).join(' ')} | shown: ${shown.join(' ')} | '
        '${router.urlState.url} | callers: $answers';
  }

  // [state] when the stack is [stack], whose top page alone a tap reaches,
  // the url names that page, and the callers heard [answers].
  String agreeing(List<String> stack, [List<String?> answers = const []]) {
    final top = stack.lastOrNull ?? 'nothing';
    return '${stack.join(' ')} | shown: $top | ${paths[top] ?? 'no url'} | '
        'callers: $answers';
  }

  for (final meanwhile in _Meanwhile.values) {
    for (final isLetIn in [true, false]) {
      final answer = isLetIn ? 'yes' : 'no';
      testWidgets('A page held back while its guard is asked again leaves '
          'the screen; then ${meanwhile.name}, then the guard says '
          '$answer', (tester) async {
        final router = buildRouter();
        await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
        unawaited(router.push(const NamedRoute('NotesRoute')));
        await tester.pumpAndSettle();
        final answers = <String?>[];
        unawaited(
          router
              .push<String>(const NamedRoute('AccountRoute'))
              .then(answers.add),
        );
        await tester.pumpAndSettle();

        isSignedIn.value = false;
        await tester.pumpAndSettle();
        // What the test sees after each step.
        final seen = [state(router, answers)];

        var shownBeforeAnswer = ['HomeRoute', 'NotesRoute'];
        switch (meanwhile) {
          case .nothing:
            break;
          case .pop:
            router.pop();
            shownBeforeAnswer = ['HomeRoute'];
          case .systemBack:
            expect(await tester.binding.handlePopRoute(), isTrue);
            shownBeforeAnswer = ['HomeRoute'];
          case .push:
            unawaited(router.push(const NamedRoute('DetailsRoute')));
            shownBeforeAnswer = ['HomeRoute', 'NotesRoute', 'DetailsRoute'];
          case .replace:
            unawaited(router.replace(const NamedRoute('OtherRoute')));
            shownBeforeAnswer = ['HomeRoute', 'OtherRoute'];
          case .rebuild:
            router.notifyAll();
        }
        await tester.pumpAndSettle();
        seen.add(state(router, answers));

        _answer?.call(isLetIn: isLetIn);
        await tester.pumpAndSettle();
        seen.add(state(router, answers));

        expect(tester.takeException(), isNull);
        expect(seen, [
          agreeing(['HomeRoute', 'NotesRoute']),
          agreeing(shownBeforeAnswer),
          if (isLetIn)
            agreeing([...shownBeforeAnswer, 'AccountRoute'])
          else
            agreeing(shownBeforeAnswer, [null]),
        ]);
        expect(accountHeard, ['removed']);
        if (isLetIn) {
          unawaited(router.maybePop('saved'));
          await tester.pumpAndSettle();
          expect(answers, ['saved']);
        }
      });
    }
  }

  testWidgets('The pages above a held-back page leave the screen with it, '
      'and come back with it', (tester) async {
    final router = buildRouter();
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    for (final name in ['AccountRoute', 'DetailsRoute']) {
      unawaited(router.push(NamedRoute(name)));
      await tester.pumpAndSettle();
    }

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    final whileHeld = state(router);

    _answer?.call(isLetIn: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(whileHeld, agreeing(['HomeRoute']));
    expect(
      state(router),
      agreeing(['HomeRoute', 'AccountRoute', 'DetailsRoute']),
    );
  });

  // Passes before the fix too: a guard that awaits its answer inside its
  // call keeps its page on the stack and on screen until it answers.
  testWidgets('A guard that awaits its answer inside its call keeps its page '
      'while it decides', (tester) async {
    final check = Completer<bool>();
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          guard: AutoRouteGuard.simple((resolver, _) async {
            if (isSignedIn.value) return resolver.next();
            (await check.future) ? resolver.next() : resolver.reject();
          }),
        ),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();

    isSignedIn.value = false;
    await tester.pumpAndSettle();
    final whileDeciding = names(router);
    final shownWhileDeciding = find.text('AccountRoute').evaluate().length;
    check.complete(false);
    await tester.pumpAndSettle();

    expect(whileDeciding, ['HomeRoute', 'AccountRoute']);
    expect(shownWhileDeciding, 1);
    expect(state(router), agreeing(['HomeRoute']));
  });

  // Where the guards asked again meet the guards of a nested router not
  // built yet (the nested-guards piece of batch 3): a guard there that says
  // no takes back the page the navigation put on, and a navigation into an
  // open page's router keeps the pages over that page until its guards
  // answer. The guard of Message decides when the test answers. A sign-out
  // that lands while it is at its check waits for its answer, and makes a
  // yes from before the change stale, so it is asked again.
  group('With a guard of a nested router', () {
    late List<Completer<bool>> messageAsks;

    setUp(() => messageAsks = []);

    final messageGuard = AutoRouteGuard.simple((resolver, _) async {
      final ask = Completer<bool>();
      messageAsks.add(ask);
      await ask.future ? resolver.next() : resolver.reject();
    });

    List<NamedRouteDef> mailbox() => [
      page('InboxRoute', ''),
      page('MessageRoute', 'message/:id', guard: messageGuard),
    ];

    // The root's pages, the pages of the router of [inside], and the url.
    String where(RootStackRouter router, String inside) {
      final inner = router.innerRouterOf<StackRouter>(inside);
      return '${names(router).join(' ')} | '
          '$inside: ${inner == null ? 'none' : names(inner).join(' ')} | '
          '${router.urlState.url}';
    }

    RootStackRouter mailRouter() => .build(
      routes: [
        page('HomeRoute', '/'),
        page('AccountRoute', '/account', guard: _sessionGuard(isSignedIn)),
        NamedRouteDef(
          name: 'MailRoute',
          path: '/mail',
          builder: (_, _) => const Scaffold(body: AutoRouter()),
          children: mailbox(),
        ),
      ],
    );

    for (final isAccountBackFirst in [false, true]) {
      testWidgets('A page its guard let go of comes back over the pages a '
          "nested guard's no leaves; the guard says yes "
          '${isAccountBackFirst ? 'before' : 'after'} the no', (tester) async {
        final router = mailRouter();
        await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
        final answers = <String>[];
        unawaited(
          router
              .push<String>(const NamedRoute('AccountRoute'))
              .then(
                (result) => answers.add('Account: ${result ?? 'no result'}'),
              ),
        );
        await tester.pumpAndSettle();
        isSignedIn.value = false;
        await tester.pumpAndSettle();
        unawaited(
          router
              .pushPath<Object?>('/mail/message/77')
              .then((result) => answers.add('Mail: ${result ?? 'no result'}')),
        );
        await tester.pumpAndSettle();
        final seen = [where(router, 'MailRoute')];

        if (isAccountBackFirst) {
          _answer?.call(isLetIn: true);
          await tester.pumpAndSettle();
          seen.add(where(router, 'MailRoute'));
        }
        messageAsks.lastOrNull?.complete(false);
        await tester.pumpAndSettle();
        seen.add(where(router, 'MailRoute'));
        if (!isAccountBackFirst) {
          _answer?.call(isLetIn: true);
          await tester.pumpAndSettle();
          seen.add(where(router, 'MailRoute'));
        }

        expect(tester.takeException(), isNull);
        expect(seen, [
          'HomeRoute MailRoute | MailRoute:  | /mail/message/77',
          if (isAccountBackFirst)
            'HomeRoute MailRoute AccountRoute | MailRoute:  | /account'
          else
            'HomeRoute | MailRoute: none | /',
          'HomeRoute AccountRoute | MailRoute: none | /account',
        ]);
        expect(find.text('AccountRoute'), findsOneWidget);
        expect(answers, ['Mail: no result']);
      });
    }

    testWidgets('A sign-out while a nested guard decides about a page over '
        "a held guard's page waits for that guard; its no takes the page "
        'back, and the page let go of comes back alone', (tester) async {
      final router = mailRouter();
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      final answers = <String>[];
      unawaited(
        router
            .push<String>(const NamedRoute('AccountRoute'))
            .then((result) => answers.add('Account: ${result ?? 'no result'}')),
      );
      await tester.pumpAndSettle();
      unawaited(
        router
            .pushPath<Object?>('/mail/message/77')
            .then((result) => answers.add('Mail: ${result ?? 'no result'}')),
      );
      await tester.pumpAndSettle();
      isSignedIn.value = false;
      await tester.pumpAndSettle();
      final seen = [where(router, 'MailRoute')];

      messageAsks.lastOrNull?.complete(false);
      await tester.pumpAndSettle();
      seen.add(where(router, 'MailRoute'));
      _answer?.call(isLetIn: true);
      await tester.pumpAndSettle();
      seen.add(where(router, 'MailRoute'));

      expect(tester.takeException(), isNull);
      expect(seen, [
        'HomeRoute AccountRoute MailRoute | MailRoute:  | /mail/message/77',
        'HomeRoute | MailRoute: none | /',
        'HomeRoute AccountRoute | MailRoute: none | /account',
      ]);
      expect(messageAsks, hasLength(1));
      expect(answers, ['Mail: no result']);
    });

    for (final isLetIn in [false, true]) {
      testWidgets('Pages over an open page wait for its nested guard while a '
          'sign-out lets go of the top one; the nested guard says '
          '${isLetIn ? 'yes' : 'no'}', (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => const Scaffold(body: AutoRouter()),
              children: mailbox(),
            ),
            page('SettingsRoute', '/settings'),
            page('AccountRoute', '/account', guard: _sessionGuard(isSignedIn)),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
        for (final name in ['SettingsRoute', 'AccountRoute']) {
          unawaited(router.push(NamedRoute(name)));
          await tester.pumpAndSettle();
        }
        unawaited(router.navigatePath('/message/77'));
        await tester.pumpAndSettle();
        isSignedIn.value = false;
        await tester.pumpAndSettle();
        final seen = [where(router, 'HomeRoute')];

        // Its answer is from before the sign-out: a yes is asked again.
        messageAsks.firstOrNull?.complete(isLetIn);
        await tester.pumpAndSettle();
        seen.add(where(router, 'HomeRoute'));
        if (isLetIn) {
          messageAsks.lastOrNull?.complete(true);
          await tester.pumpAndSettle();
          seen.add(where(router, 'HomeRoute'));
        }
        _answer?.call(isLetIn: true);
        await tester.pumpAndSettle();
        seen.add(where(router, 'HomeRoute'));

        expect(tester.takeException(), isNull);
        expect(messageAsks, hasLength(isLetIn ? 2 : 1));
        // [where] for Home's router, Inbox under Message when [isOpen].
        String home(String root, String url, {bool isOpen = false}) =>
            '$root | HomeRoute: InboxRoute${isOpen ? ' MessageRoute' : ''} '
            '| $url';
        expect(seen, [
          home('HomeRoute SettingsRoute AccountRoute', '/account'),
          home('HomeRoute SettingsRoute', '/settings'),
          if (isLetIn) ...[
            home('HomeRoute', '/message/77', isOpen: true),
            // The page let go of was off the stack when the navigation
            // closed the pages over Home, so it comes back on its yes.
            home('HomeRoute AccountRoute', '/account', isOpen: true),
          ] else
            home('HomeRoute SettingsRoute AccountRoute', '/account'),
        ]);
      });
    }
  });
}
