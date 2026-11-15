import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// What an AutoRouteLeaveListener hears in a page that replaceAll sets aside
// for the page of a guard. A lead of the audit of auto_route/lib asked
// whether "replaced" is wrong when the guard then rejects and the page comes
// back. It is not, and this test documents it; nothing was changed.
// Setup: Home sits behind a guard that sends a signed-out user to a login
// page with redirectUntil. Account holds an AutoRouteLeaveListener.
// Steps: signed in, open Home and Account. Sign out and call
// replaceAll([HomeRoute()]): the login page takes the place of the pages.
// The guard rejects, as a cancel button does, and the pages come back.
// What happens: Account's listener hears "replaced" as the login page goes
// on, and nothing as Account comes back. That is what happened to the
// screen: it left the navigator for the login page, with its state, and its
// listener went with it. The Account that comes back is a screen built anew,
// with a listener of its own that has heard nothing yet. Flutter's Navigator
// disposes the route of a page that leaves its list and makes a new one for
// a page given to it again, and Android destroys an activity that is cleared
// from its task and creates a new one when the user returns to it.
void main() {
  testWidgets('The leave listener of a page a guard of replaceAll set aside '
      'hears that it was replaced, and the page that comes back is a new '
      'screen', (tester) async {
    final isSignedIn = ValueNotifier(true);
    addTearDown(isSignedIn.dispose);
    final signingIn = <NavigationResolver>[];
    // What each Account screen heard, in the order the screens were built.
    final heard = <List<RouteLeaveKind>>[];
    NamedRouteDef page(String name, String path, [AutoRouteGuard? guard]) =>
        .new(
          name: name,
          path: path,
          guards: [?guard],
          builder: (_, _) => name == 'AccountRoute'
              ? _Listening(heard: heard)
              : Scaffold(body: Text(name)),
        );
    final router = RootStackRouter.build(
      routes: [
        page(
          'HomeRoute',
          '/',
          AutoRouteGuard.simple((resolver, _) {
            if (isSignedIn.value) return resolver.next();
            signingIn.add(resolver);
            unawaited(resolver.redirectUntil(const NamedRoute('LoginRoute')));
          }),
        ),
        page('AccountRoute', '/account'),
        page('LoginRoute', '/login'),
      ],
    );
    await pumpRouterApp(tester, router);
    unawaited(router.push(const NamedRoute('AccountRoute')));
    await tester.pumpAndSettle();
    isSignedIn.value = false;
    final failures = <NavigationFailure>[];
    unawaited(
      router.replaceAll([
        const NamedRoute('HomeRoute'),
      ], onFailure: failures.add),
    );
    await tester.pumpAndSettle();
    // What each screen has heard so far, as one string per screen.
    List<String> told() => [
      for (final kinds in heard) kinds.map((kind) => kind.name).join(' '),
    ];
    final atLogin = told();

    signingIn.singleOrNull?.reject();
    await tester.pumpAndSettle();
    final screensAfterReject = heard.length;
    router.pop();
    await tester.pumpAndSettle();

    expect(atLogin, ['replaced']);
    // The Account that is back is a second screen, which hears only its own
    // pop.
    expect(screensAfterReject, 2);
    expect(told(), ['replaced', 'popped']);
    expect(failures.singleOrNull, isA<RejectedByGuardFailure>());
  });
}

// An Account screen that adds the list of what it hears to [heard] as it is
// built for the first time.
class _Listening extends StatefulWidget {
  const new({required this.heard});

  final List<List<RouteLeaveKind>> heard;

  @override
  State<_Listening> createState() => _ListeningState();
}

class _ListeningState extends State<_Listening> {
  final _kinds = <RouteLeaveKind>[];

  @override
  void initState() {
    super.initState();
    widget.heard.add(_kinds);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AutoRouteLeaveListener(
      onLeave: _kinds.add,
      child: const Text('AccountRoute'),
    ),
  );
}
