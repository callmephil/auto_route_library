import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A sign-out did not close a guarded page while the guard of a push awaited
// a request. Fixes callmephil/auto_route_library#1.
// Setup: Home, Secret and Offer. Secret's guard lets a signed-in user
// through and rejects the others. Offer's guard reads the session, then
// awaits a request inside its call, then answers from what it read. The
// session is the router's reevaluateListenable.
// Steps: the app pushes Secret, then opens Offer (push, replace, pushAll or
// navigate) and the request does not complete. The user signs out and the
// app calls reevaluateGuards(). Then the request completes.
// Was: Secret stayed for the signed-out user, and reevaluateGuards() did
// not complete, until the request completed.
// _composeMatchesForReevaluate awaited NavigationResolver.checkGuard for a
// navigation's guard at its check before it asked any page.
// Should: the sign-out closes Secret at once and reevaluateGuards()
// completes. The yes of Offer's first call, from before the sign-out, is
// dropped, the guard is asked again, and its no opens nothing.
// Native behavior this holds to: Flutter's Router drops the work of an older
// route transaction when newer route information arrives
// (_processParsedRouteInformation, router.dart, Flutter 3.50.0): a later
// change never waits for an earlier one.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  void set({required bool signedIn}) {
    isSignedIn = signedIn;
    notifyListeners();
  }
}

void main() {
  late _Session session;

  setUp(() {
    session = _Session();
    addTearDown(session.dispose);
  });

  NamedRouteDef page(String name, String path, AutoRouteGuard guard) => .new(
    name: name,
    path: path,
    guards: [guard],
    builder: (_, _) => Scaffold(body: Text(name)),
  );

  List<String> names(StackRouter router) =>
      router.stack.map((page) => page.routeData.name).toList();

  const offer = NamedRoute('OfferRoute');
  final opens = <String, void Function(StackRouter router)>{
    'push': (router) => unawaited(router.push(offer)),
    'replace': (router) => unawaited(router.replace(offer)),
    'pushAll': (router) => unawaited(router.pushAll([offer])),
    'navigate': (router) => unawaited(router.navigate(offer)),
  };

  for (final MapEntry(key: name, value: open) in opens.entries) {
    testWidgets('A sign-out closes Secret at once while the guard of $name '
        'awaits a request', (tester) async {
      final request = Completer<void>();
      var offerAsks = 0;
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HomeRoute')),
          ),
          page(
            'SecretRoute',
            '/secret',
            AutoRouteGuard.simple(
              (resolver, _) =>
                  session.isSignedIn ? resolver.next() : resolver.reject(),
            ),
          ),
          page(
            'OfferRoute',
            '/offer',
            AutoRouteGuard.simple((resolver, _) async {
              offerAsks++;
              final isSignedIn = session.isSignedIn;
              if (offerAsks == 1) await request.future;
              isSignedIn ? resolver.next() : resolver.reject();
            }),
          ),
        ],
      );
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('SecretRoute')));
      await tester.pumpAndSettle();
      open(router);
      await tester.pumpAndSettle();

      var isDone = false;
      session.isSignedIn = false;
      unawaited(router.reevaluateGuards().then((_) => isDone = true));
      await tester.pumpAndSettle();
      final stackAfterSignOut = names(router);
      final (isDoneAfterSignOut, asksAfterSignOut) = (isDone, offerAsks);
      request.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stackAfterSignOut, ['HomeRoute']);
      expect((isDoneAfterSignOut, asksAfterSignOut), (true, 1));
      // Asked again once its first call answered from before the sign-out.
      expect(offerAsks, 2);
      expect(names(router), ['HomeRoute']);
      expect(find.text('OfferRoute'), findsNothing);
    });
  }
}
