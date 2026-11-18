import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// After replaceAll, the push() of a page held for its guard waited for that
// guard's answer. Fixes callmephil/auto_route_library#3.
// Setup: Home, Account and Other. Account's guard lets a signed-in user
// through and returns without an answer for the others. The session is the
// router's reevaluateListenable.
// Steps: the app pushes Account and keeps its future. The user signs out:
// Account's guard returns without an answer, so Account is held off the
// screen until it answers. The app calls replaceAll([Other]). The session
// notifies three times, then the user signs in again.
// Was: the push() future completed only at the sign-in, and each change
// called Account's guard again for a page that replaceAll had removed.
// _awaitLetGoAnswer waited for the guard's answer, and replaceAll did not
// end that wait.
// Should: the push() future completes with null at the replaceAll, no
// change calls the guard again, and a later yes opens nothing.
// Native behavior this holds to: Flutter's Navigator completes each route
// that pushAndRemoveUntil removes, with null, at the removal
// (Navigator.pushAndRemoveUntil, navigator.dart, Flutter 3.50.0).
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void set({required bool signedIn}) {
    isSignedIn = signedIn;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

void main() {
  late _Session session;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
  });

  NamedRouteDef page(String name, String path, {AutoRouteGuard? guard}) => .new(
    name: name,
    path: path,
    guards: [?guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  testWidgets('replaceAll ends the wait of a page held for its guard', (
    tester,
  ) async {
    var asks = 0;
    final answers = <NavigationResolver>[];
    final router = RootStackRouter.build(
      routes: [
        page('HomeRoute', '/'),
        page(
          'AccountRoute',
          '/account',
          guard: AutoRouteGuard.simple((resolver, _) {
            asks++;
            answers.add(resolver);
            if (session.isSignedIn) resolver.next();
          }),
        ),
        page('OtherRoute', '/other'),
      ],
    );
    await pumpRouterApp(tester, router, reevaluationNotifier: session);
    final results = <Object?>[];
    unawaited(
      router.push<String>(const NamedRoute('AccountRoute')).then(results.add),
    );
    await tester.pumpAndSettle();

    session.set(signedIn: false);
    await tester.pumpAndSettle();
    expect(names(router), ['HomeRoute']);
    unawaited(router.replaceAll([const NamedRoute('OtherRoute')]));
    await tester.pumpAndSettle();
    final stackAfterReplaceAll = names(router);
    final resultsAfterReplaceAll = List.of(results);

    asks = 0;
    for (var times = 0; times < 3; times++) {
      session.refresh();
      await tester.pumpAndSettle();
    }
    final asksAfter = asks;
    session.set(signedIn: true);
    await tester.pumpAndSettle();
    // A late yes of an earlier ask opens nothing either.
    for (final resolver in answers) {
      if (!resolver.isResolved) resolver.next();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stackAfterReplaceAll, ['OtherRoute']);
    expect(resultsAfterReplaceAll, [null]);
    expect(asksAfter, 0);
    expect(names(router), ['OtherRoute']);
    expect(find.text('AccountRoute'), findsNothing);
    expect(results, [null]);
  });
}
