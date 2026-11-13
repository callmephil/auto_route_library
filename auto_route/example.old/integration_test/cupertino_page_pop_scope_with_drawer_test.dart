import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Back on a Cupertino page asks its PopScope first, also while its drawer is
// open.
// Headless test: auto_route/test/cupertino_page_pop_scope_with_drawer_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('cupertino page pop scope with drawer', () {
    // Steps: push a Cupertino page wrapped in PopScope(canPop: false) whose
    // Scaffold has a drawer, tap 'Open drawer', go back.
    // Was: the drawer closed and the PopScope heard nothing.
    // Should: the PopScope hears the refused back and the drawer stays, as
    // with Flutter's own CupertinoPageRoute, which asks the PopScopes before
    // its local history.
    testWidgets('the PopScope hears back and the drawer stays', (
      tester,
    ) async {
      final heard = ValueNotifier<List<bool>>(const []);
      addTearDown(heard.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          NamedRouteDef(
            name: 'FormRoute',
            path: '/form',
            type: const RouteType.cupertino(),
            builder: (_, _) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) =>
                  heard.value = [...heard.value, didPop],
              child: Scaffold(
                drawer: const Drawer(child: Text('Drawer')),
                body: Builder(
                  builder: (context) => SafeArea(
                    child: TextButton(
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      child: const Text('Open drawer'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await pumpRouterApp(tester, router);
      unawaited(router.pushPath('/form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open drawer'));
      await tester.pumpAndSettle();
      final drawersBefore = find.text('Drawer').evaluate().length;

      await systemBack(tester);
      expect(heard.value, [false]);
      expect((drawersBefore, find.text('Drawer').evaluate().length), (1, 1));
      expect(router.current.name, 'FormRoute');
    });
  });
}
