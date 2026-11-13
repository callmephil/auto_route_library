import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page the app replaces while a slow guard is asked again stays off when
// the guard then lets its page stay, as Flutter's Navigator shows the list
// of pages it was given last, whatever an older caller still awaits.
// Headless test: auto_route/test/reevaluatable_router/page_taken_off_while_reevaluating_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('page taken off while reevaluating', () {
    // Steps: open Home, then Account and Bills, both behind a guard that
    // awaits a session check when it is asked again. The session changes, so
    // the guards are asked again. While Account's guard waits, call
    // replace(OtherRoute()). The check ends and the guard lets Account stay.
    // Go back from Other.
    // Was: the stack was [Home, Account, Bills, Other], and back from Other
    // showed Bills, which the app had replaced.
    // Should: [Home, Account, Other], and back shows Account.
    testWidgets('A page replaced while a slow guard is asked again does not '
        'come back', (tester) async {
      final session = ValueNotifier(0);
      addTearDown(session.dispose);
      final check = Completer<void>();
      final guard = AutoRouteGuard.simple((resolver, _) async {
        if (resolver.isReevaluating) await check.future;
        resolver.next();
      });
      NamedRouteDef page(String name, String path, [AutoRouteGuard? asked]) =>
          .new(
            name: name,
            path: path,
            guards: [?asked],
            builder: (_, _) => Scaffold(body: SafeArea(child: Text(name))),
          );
      final router = RootStackRouter.build(
        routes: [
          page('HomeRoute', '/'),
          page('AccountRoute', '/account', guard),
          page('BillsRoute', '/bills', guard),
          page('OtherRoute', '/other'),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.push(const NamedRoute('AccountRoute')));
      await tester.pumpAndSettle();
      unawaited(router.push(const NamedRoute('BillsRoute')));
      await tester.pumpAndSettle();
      expectTopPage(router, 'BillsRoute');

      session.value++;
      await tester.pumpAndSettle();
      unawaited(router.replace(const NamedRoute('OtherRoute')));
      await tester.pumpAndSettle();
      check.complete();
      await tester.pumpAndSettle();

      expectTopPage(router, 'OtherRoute');
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'AccountRoute',
        'OtherRoute',
      ]);
      await expectBrowserUrl('/other');

      unawaited(router.maybePop());
      await tester.pumpAndSettle();

      expectTopPage(router, 'AccountRoute');
      expect(find.text('BillsRoute'), findsNothing);
      await expectBrowserUrl('/account');
    });
  });
}
