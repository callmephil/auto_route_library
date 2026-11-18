import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A guard whose call returned without an answer held up every later
// reevaluation. Found by the review of 7c67ead5 (its finding 6), on dev
// 921fce58 too.
// Setup: Home and Account. Account's guard lets a signed-in user through
// and rejects the others. The session is the router's reevaluateListenable.
// Steps: the app pushes Settings, whose guard returns without an answer and
// answers later from a callback, as one that asks a service does. While it
// has not answered, the user signs out.
// Was: the sign-out asked no guard of the pages on the stack: Account stayed
// for the signed-out user, and reevaluateGuards() never completed. Every
// reevaluation asked each unanswered guard of activeGuardObserver again and
// awaited its answer before it asked any page.
// Should: the guard of the push is asked again without the round waiting
// for it, and the sign-out closes Account. A guard that waits on the user
// in a page or a dialog it showed keeps the round open, as the README says,
// but a later change doesn't call it again: it would show its dialog twice.
// Native behavior this holds to: Flutter's Router drops an older route
// transaction's work once newer route information has arrived
// (_currentRouterTransaction, router.dart), so a later change is never
// blocked by one that hangs. That a guard waiting on the user in a dialog
// isn't called again, so the dialog is shown once, is this package's own
// rule; no native source says an alert is shown once.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void set({required bool signedIn}) {
    isSignedIn = signedIn;
    notifyListeners();
  }
}

void main() {
  late _Session session;
  late List<NavigationResolver> settingsAsks;
  late int accountAsks;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
    settingsAsks = [];
    accountAsks = 0;
  });

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('A push whose guard returned without an answer holds no '
      'reevaluation up', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          guard: AutoRouteGuard.simple((resolver, _) {
            accountAsks++;
            session.isSignedIn ? resolver.next() : resolver.reject();
          }),
        ),
        page(
          'SettingsRoute',
          '/settings',
          guard: AutoRouteGuard.simple(
            (resolver, _) => settingsAsks.add(resolver),
          ),
        ),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('SettingsRoute')));
    await tester.pumpAndSettle();

    var isDone = false;
    session.set(signedIn: false);
    unawaited(router.reevaluateGuards().then((_) => isDone = true));
    await tester.pumpAndSettle();
    final afterSignOut = (names(router), isDone, accountAsks);
    // The push still goes on once its guard answers. A yes given during
    // the reevaluation's own ask is from before the second change of this
    // turn, so the guard is asked once more and answers again.
    for (var times = 0; times < 3; times++) {
      for (final resolver in {...settingsAsks}) {
        if (!resolver.isResolved) resolver.next();
      }
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
    expect(afterSignOut.$1, ['HomeRoute']);
    // reevaluateGuards() completed, and Account's guard was asked again.
    expect((afterSignOut.$2, afterSignOut.$3), (true, 2));
    expect(names(router), ['HomeRoute', 'SettingsRoute']);
  });

  for (final isPush in [false, true]) {
    final asked = isPush ? 'for a push' : 'asked again';
    testWidgets('A guard $asked that shows a dialog and returns is not called '
        'again by a later change while its dialog is open', (tester) async {
      var dialogs = 0;
      final guard = AutoRouteGuard.simple((resolver, router) {
        if (session.isSignedIn && !isPush) return resolver.next();
        dialogs++;
        unawaited(
          showDialog<bool>(
            context: router.navigatorKey.currentContext!,
            builder: (dialog) => AlertDialog(
              title: Text('Stay $dialogs?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(true),
                  child: const Text('Yes'),
                ),
              ],
            ),
          ).then((isYes) => (isYes ?? false) ? resolver.next() : null),
        );
      });
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('AccountRoute', '/account', guard: guard),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      if (!isPush) {
        session.set(signedIn: false);
        await tester.pumpAndSettle();
      }

      unawaited(router.reevaluateGuards());
      await tester.pumpAndSettle();
      final dialogsAfterChange = dialogs;
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(dialogsAfterChange, 1);
      expect(names(router), ['HomeRoute', 'AccountRoute']);
      expect(find.text('AccountRoute'), findsOneWidget);
    });
  }

  // Finding B of the second review. Steps: on Home, Secret (its guard
  // rejects a signed-out user), the app calls push, replace, pushAll or
  // navigate to Pushed, whose guard returns and answers later from a
  // callback. The user signs out. Then the callback says yes, or no.
  // Was: the sign-out asked the guard again on the same resolver, and the
  // callback's yes, from before the sign-out, opened Pushed for the
  // signed-out user.
  // Should: that yes is from before the last change: it opens nothing, and
  // the guard is asked again before Pushed goes in, as a guard that awaits
  // inside its call already is (_canNavigate). Since
  // callmephil/auto_route_library#4 each call of the guard gets a resolver
  // of its own, and only the latest call decides: the sign-out's call is
  // the latest, so the first call's yes or no is ignored either way.
  // Native behavior this holds to: Flutter's Router drops an older route
  // transaction's result once newer route information has arrived
  // (_processParsedRouteInformation, router.dart).
  for (final op in ['push', 'replace', 'pushAll', 'navigate']) {
    for (final isYes in [true, false]) {
      testWidgets('A $op whose guard answers from a callback: its '
          '${isYes ? 'yes' : 'no'} from before a sign-out opens nothing', (
        tester,
      ) async {
        final router = RootStackRouter.build(
          routes: [
            page('HomeRoute', '/'),
            page('OtherRoute', '/other'),
            page(
              'SecretRoute',
              '/secret',
              guard: AutoRouteGuard.simple(
                (resolver, _) =>
                    session.isSignedIn ? resolver.next() : resolver.reject(),
              ),
            ),
            page(
              'PushedRoute',
              '/pushed',
              guard: AutoRouteGuard.simple(
                (resolver, _) => settingsAsks.add(resolver),
              ),
            ),
          ],
        );
        await pumpRouterApp(tester, router, reevaluationNotifier: session);
        unawaited(router.push(const NamedRoute('SecretRoute')));
        await tester.pumpAndSettle();
        const target = NamedRoute('PushedRoute');
        switch (op) {
          case 'push':
            unawaited(router.push(target));
          case 'replace':
            unawaited(router.replace(target));
          case 'pushAll':
            unawaited(router.pushAll(const [NamedRoute('OtherRoute'), target]));
          case _:
            unawaited(router.navigate(target));
        }
        await tester.pumpAndSettle();
        final firstAsk = settingsAsks.firstOrNull;

        session.set(signedIn: false);
        await tester.pumpAndSettle();
        final afterSignOut = names(router);
        isYes ? firstAsk?.next() : firstAsk?.reject();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(afterSignOut, isNot(contains('SecretRoute')));
        expect(names(router), isNot(contains('PushedRoute')));
        expect(names(router), isNotEmpty);
        // The first call, and the one the sign-out made, which decides.
        expect(settingsAsks.toSet(), hasLength(2));
      });
    }
  }
}
