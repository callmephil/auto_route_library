import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A pop while a guard that was asked again had not answered emptied the
// stack or closed the wrong page. Found by the review of cb0265d5, which
// brought it.
// Steps: Account's guard lets its page in as it opens. Asked again, it
// returns without an answer and shows no page, as a guard that starts a
// session check and answers from its callback does. Open Home, Account,
// Bills, or Home, Notes, Account, or Home, Account. The session changes,
// so the guard is asked again: its page and the pages above it are held
// off the stack until it answers, and stay on screen. Before it answers,
// call pop or maybePop, or press the system back button. Then the guard
// answers.
// Was: on Home, Account, Bills a pop left no page on the stack and none on
// screen, and maybePop and the system back button closed nothing and
// answered false. On Home, Notes, Account a pop closed Notes, the page
// under the one on screen.
// The cause: before it hands a pop to the navigator, the router takes out
// the routes of pages that left the stack and still lie over its top page
// (cb0265d5). It took the held-back pages for such pages, so their routes
// went, and the pop then closed the page under them.
// Should: the pop closes the page on screen, which stays closed whatever
// the guard answers, and the pages under it are as the guard decides.
// Since Phil's decision 4 of 2026-11-16 the held-back pages leave the
// screen at once (held_back_page_leaves_screen_test.dart), so the page on
// screen is the one under Account: a pop closes Notes, and on Home alone
// there is nothing to pop. A later yes puts Account back on top, with the
// pages that were above it.
// Native behavior this holds to: Flutter's Navigator.pop closes the route
// on top, the one the user sees. On Android a back press finishes the
// activity on screen, and on a root activity it leaves the app.
void Function({required bool isLetIn})? _answer;
var _isAskedAgain = false;

class _Session extends ChangeNotifier {
  void changed() => notifyListeners();
}

// Lets its page in at once when it opens. Asked again, it returns without an
// answer and answers from the callback the test calls.
final _guard = AutoRouteGuard.simple((resolver, _) {
  if (!_isAskedAgain) return resolver.next();
  _answer = ({required isLetIn}) =>
      isLetIn ? resolver.next() : resolver.reject();
});

RootStackRouter _router() => .build(
  routes: [
    for (final (name, path, isGuarded) in [
      ('HomeRoute', '/', false),
      ('NotesRoute', '/notes', false),
      ('AccountRoute', '/account', true),
      ('BillsRoute', '/bills', false),
    ])
      NamedRouteDef(
        name: name,
        path: path,
        guards: [if (isGuarded) _guard],
        builder: (_, _) => Scaffold(body: Text(name)),
      ),
  ],
);

String _names(StackRouter router) =>
    router.stack.map((page) => page.routeData.name).join(' ');

// The pages a tap could reach, bottom first.
String _onScreen() => [
  for (final name in ['HomeRoute', 'NotesRoute', 'AccountRoute', 'BillsRoute'])
    if (find.text(name).hitTestable().evaluate().isNotEmpty) name,
].join('+');

void main() {
  setUp(() {
    _answer = null;
    _isAskedAgain = false;
  });

  // Each checks, where it answers, whether it closed a page as [isPopping]
  // says it should.
  final pops =
      <
        String,
        FutureOr<void> Function(
          WidgetTester,
          StackRouter, {
          required bool isPopping,
        })
      >{
        'pop': (_, router, {required isPopping}) => router.pop(),
        'maybePop': (_, router, {required isPopping}) async =>
            expect(await router.maybePop(), isPopping),
        'the system back button': (tester, _, {required isPopping}) async =>
            expect(await tester.binding.handlePopRoute(), isPopping),
      };

  // The pages opened over Home.
  for (final opened in [
    ['AccountRoute', 'BillsRoute'],
    ['NotesRoute', 'AccountRoute'],
    ['AccountRoute'],
  ]) {
    for (final MapEntry(key: call, value: pop) in pops.entries) {
      // pop on the root's one page takes it off, as Flutter's Navigator.pop
      // does, guard or not: not what this test is about.
      if (call == 'pop' && opened.firstOrNull == 'AccountRoute') continue;
      for (final isLetIn in [true, false]) {
        testWidgets('On Home, ${opened.join(', ')}, while the guard of '
            'Account, asked again, has not answered, $call acts on the page '
            'on screen; then the guard '
            '${isLetIn ? 'lets its page stay' : 'rejects'}', (tester) async {
          final session = _Session();
          addTearDown(session.dispose);
          final router = _router();
          await pumpRouterApp(tester, router, reevaluationNotifier: session);
          for (final name in opened) {
            unawaited(router.push(NamedRoute(name)));
            await tester.pumpAndSettle();
          }
          final guardedAt = opened.indexOf('AccountRoute') + 1;
          final shownWhileHeld = ['HomeRoute', ...opened.take(guardedAt - 1)];
          final isPopping = shownWhileHeld.length > 1;

          _isAskedAgain = true;
          session.changed();
          await tester.pumpAndSettle();
          final whileHeld = (_names(router), _onScreen());
          await pop(tester, router, isPopping: isPopping);
          await tester.pumpAndSettle();
          final afterCall = (_names(router), _onScreen());
          _answer?.call(isLetIn: isLetIn);
          await tester.pumpAndSettle();

          final afterPop = isPopping
              ? shownWhileHeld.take(shownWhileHeld.length - 1).toList()
              : shownWhileHeld;
          final left = [
            ...afterPop,
            if (isLetIn) ...opened.skip(guardedAt - 1),
          ];
          expect(tester.takeException(), isNull);
          // Held off the stack and the screen from Account up.
          expect(whileHeld, (
            shownWhileHeld.join(' '),
            shownWhileHeld.lastOrNull,
          ));
          expect(afterCall, (afterPop.join(' '), afterPop.lastOrNull));
          expect(
            (_names(router), _onScreen()),
            (left.join(' '), left.lastOrNull),
          );
        });
      }
    }
  }
}
