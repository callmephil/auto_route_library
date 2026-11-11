import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/pages.dart';

// A shell whose screen replaceAll keeps below the top shows the children
// replaceAll names for it.
// Headless test: replace_all_kept_screen_shows_new_children_test.dart in
// the auto_route package's test/simple_router folder.
// Flutter's Navigator updates a keyless page's route in place and builds the
// new page's content, so a nested Navigator in it shows the new children.
// SwiftUI's NavigationStack hands a screen kept at its place its new value
// through onChange, and Android hands a single-top activity the new intent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaceAll keeps a shell below the top', () {
    // Steps: push ShellRoute showing ChildARoute, push FirstRoute, replaceAll
    // with HomeRoute, ShellRoute showing ChildBRoute, and SecondRoute, then
    // go back with system back.
    // Happened: the shell kept its screen but still showed ChildARoute.
    // Should: the shell keeps its screen, and shows ChildBRoute at /shell/b.
    testWidgets('The kept shell shows the new child', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const TextPage('Home'),
          ),
          NamedRouteDef(
            name: 'FirstRoute',
            path: '/first',
            builder: (_, _) => const TextPage('First'),
          ),
          NamedRouteDef(
            name: 'SecondRoute',
            path: '/second',
            builder: (_, _) => const TextPage('Second'),
          ),
          NamedRouteDef(
            name: 'ShellRoute',
            path: '/shell',
            builder: (_, _) => const Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Text('Shell'),
                    Expanded(child: AutoRouter()),
                  ],
                ),
              ),
            ),
            children: [
              NamedRouteDef(
                name: 'ChildARoute',
                path: 'a',
                builder: (_, _) => const Text('Child A'),
              ),
              NamedRouteDef(
                name: 'ChildBRoute',
                path: 'b',
                builder: (_, _) => const Text('Child B'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterAppWithConfig(tester, router);
      unawaited(
        router.push(
          const NamedRoute('ShellRoute', children: [NamedRoute('ChildARoute')]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Child A'), findsOneWidget);
      final shellScreen = ModalRoute.of(tester.element(find.text('Shell')));
      unawaited(router.push(const NamedRoute('FirstRoute')));
      await tester.pumpAndSettle();

      unawaited(
        router.replaceAll(const [
          NamedRoute('HomeRoute'),
          NamedRoute('ShellRoute', children: [NamedRoute('ChildBRoute')]),
          NamedRoute('SecondRoute'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      await expectBrowserUrl('/second');

      await systemBack(tester);
      expect(
        ModalRoute.of(tester.element(find.text('Shell'))),
        same(shellScreen),
      );
      expect(find.text('Child B'), findsOneWidget);
      expect(find.text('Child A'), findsNothing);
      expect(router.currentUrl, '/shell/b');
      await expectBrowserUrl('/shell/b');
    });
  });
}
