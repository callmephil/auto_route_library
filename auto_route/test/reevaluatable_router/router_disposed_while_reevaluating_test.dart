import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// A router disposed while a guard that is asked again still decides asks no
// further guard. Found by the second audit of the library as a lead read
// from the code, and proven here; on the last release too.
// Setup: a shell page behind a guard that awaits a session check, with a
// nested router whose page has a guard of its own. The router reevaluates
// when the session changes.
// Steps: the session changes, and the shell's guard waits for its check. The
// app disposes the router while its widgets are still mounted, as an app
// does that swaps its router for a new one in one setState. The check ends.
// Was: the guard of the nested page was asked once more, for a router that
// was gone, and telling the disposed router of the result threw "A
// _RootStackRouterImpl was used after being disposed". The reevaluation
// checked that its router was still there only after it had asked the
// nested router of its first page.
// Should: nothing more happens. Flutter's ChangeNotifier must not be used
// once it is disposed, and the reevaluation already stops for a disposed
// router at each of its later steps.
void main() {
  testWidgets('A router disposed while a guard asked again decides asks no '
      'guard of its nested router', (tester) async {
    final asked = <String>[];
    final check = Completer<void>();
    final session = ValueNotifier(0);
    addTearDown(session.dispose);
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef.shell(
          name: 'ShellRoute',
          path: '/',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              asked.add('shell');
              if (resolver.isReevaluating) await check.future;
              resolver.next();
            }),
          ],
          children: [
            NamedRouteDef(
              name: 'AccountRoute',
              path: '',
              guards: [
                AutoRouteGuard.simple((resolver, _) {
                  asked.add('account');
                  resolver.next();
                }),
              ],
              builder: (_, _) => const Scaffold(body: Text('AccountRoute')),
            ),
          ],
        ),
      ],
    );
    final config = router.config(reevaluateListenable: session);
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();
    final atStart = List.of(asked);
    asked.clear();

    session.value++;
    await tester.pumpAndSettle();
    if (config.routerDelegate case final AutoRouterDelegate delegate) {
      delegate.dispose();
    }
    check.complete();
    await tester.pumpAndSettle();

    expect(atStart, ['shell', 'account']);
    expect(asked, ['shell']);
    expect(tester.takeException(), isNull);
  });
}
