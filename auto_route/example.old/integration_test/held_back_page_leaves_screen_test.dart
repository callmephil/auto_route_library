import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A page whose guard, asked again, returns without an answer leaves the
// stack and the screen at once, and comes back once the guard says yes
// (Phil's decision 4 of 2026-11-16), as Flutter's Navigator shows the pages
// it was last given and the address bar names the page shown.
// Headless test:
// auto_route/test/reevaluatable_router/held_back_page_leaves_screen_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('held back page leaves the screen', () {
    // Steps: open Home, Notes and Account. Account's guard lets a signed-in
    // user through and otherwise returns without an answer and answers
    // later. The session ends, then the user signs in again and the guard
    // lets Account back.
    // Was: Account stayed on screen, with its url, while the stack held Home
    // and Notes only.
    // Should: Notes shows at once, with its url; Account comes back on top
    // once its guard says yes, and back from it shows Notes.
    testWidgets('The page leaves while its guard decides', (tester) async {
      final isSignedIn = ValueNotifier(true);
      addTearDown(isSignedIn.dispose);
      final asking = <NavigationResolver>[];
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
          page('NotesRoute', '/notes'),
          page(
            'AccountRoute',
            '/account',
            AutoRouteGuard.simple((resolver, _) {
              if (isSignedIn.value) return resolver.next();
              asking.add(resolver);
            }),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router, reevaluationNotifier: isSignedIn);
      for (final name in ['NotesRoute', 'AccountRoute']) {
        unawaited(router.push(NamedRoute(name)));
        await tester.pumpAndSettle();
      }

      isSignedIn.value = false;
      await tester.pumpAndSettle();
      expectTopPage(router, 'NotesRoute');
      expect(find.text('AccountRoute'), findsNothing);
      await expectBrowserUrl('/notes');

      asking.singleOrNull?.next();
      await tester.pumpAndSettle();
      expectTopPage(router, 'AccountRoute');
      await expectBrowserUrl('/account');

      await systemBack(tester);
      expectTopPage(router, 'NotesRoute');
      expect(router.stack.map((page) => page.name), [
        'HomeRoute',
        'NotesRoute',
      ]);
      await expectBrowserUrl('/notes');
    });
  });
}
