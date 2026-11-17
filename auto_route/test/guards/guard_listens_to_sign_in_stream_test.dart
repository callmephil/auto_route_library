import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import '../centered_named_page.dart';
import '../router_test_utils.dart';

enum _Auth { signedIn, signedOut }

/// An auth source like a bloc: [state] is the current state, [stream] tells
/// each change.
class _AuthSource {
  _Auth state = _Auth.signedOut;
  final _controller = StreamController<_Auth>.broadcast();

  Stream<_Auth> get stream => _controller.stream;

  void set(_Auth next) {
    state = next;
    _controller.add(next);
  }

  Future<void> close() => _controller.close();
}

/// A guard that answers from a stream, the way README's guards section says:
/// it reads the current state first, listens only while it has no answer, and
/// stops listening once it has answered, since [NavigationResolver.next] works
/// once per ask.
class _StreamGuard extends AutoRouteGuard {
  const new(this.auth);

  final _AuthSource auth;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (auth.state == _Auth.signedIn) {
      resolver.next();
      return;
    }
    unawaited(
      resolver.redirectUntil(const NamedRoute('LoginRoute'), onFailure: (_) {}),
    );
    late final StreamSubscription<_Auth> sub;
    sub = auth.stream.listen((state) {
      if (state != _Auth.signedIn) return;
      unawaited(sub.cancel());
      if (!resolver.isResolved) resolver.next();
    });
  }
}

void main() {
  // https://github.com/Milad-Akarie/auto_route_library/issues/2051
  // The report: a guard on the account page listens to the auth bloc's stream
  // inside onNavigation and calls resolver.next() on every sign-in, without
  // ever stopping. The user signs in, signs out and signs in again; the
  // second sign-in fails with "Make sure `resolver.next()` is only called
  // once." That is the guard's misuse: an ask has one answer, so the old
  // asks' listeners must stop once they have answered, as in this test.
  // Native navigation agrees: WKNavigationDelegate raises an exception when a
  // decisionHandler is called twice, and a Dart Completer or Flutter's
  // Navigator route future completes once only.
  testWidgets('A guard that answers from a stream works at every sign-in '
      '(#2051)', (tester) async {
    final auth = _AuthSource();
    addTearDown(auth.close);
    final guard = _StreamGuard(auth);
    final reevaluate = ReevaluateListenable.stream(auth.stream);
    addTearDown(reevaluate.dispose);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const CenteredNamedPage('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'LoginRoute',
          path: '/login',
          builder: (_, _) => const CenteredNamedPage('LoginRoute'),
        ),
        NamedRouteDef(
          name: 'AccountRoute',
          path: '/account',
          guards: [guard],
          builder: (_, _) => const CenteredNamedPage('AccountRoute'),
        ),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: reevaluate);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    expect(find.text('LoginRoute'), findsOneWidget);

    for (var round = 0; round < 3; round++) {
      auth.set(_Auth.signedIn);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'sign-in $round');
      expect(find.text('AccountRoute'), findsOneWidget, reason: 'round $round');

      auth.set(_Auth.signedOut);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'sign-out $round');
      expect(find.text('LoginRoute'), findsOneWidget, reason: 'round $round');
    }
  });
}
