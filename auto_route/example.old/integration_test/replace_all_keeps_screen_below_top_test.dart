import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/pages.dart';

// replaceAll keeps the screen of a page below the top when the new stack has
// a page of the same route at its place, and the code that opened the screen
// keeps waiting until the screen closes.
// Headless test:
// auto_route/test/simple_router/replace_all_keeps_screen_below_top_test.dart
// A SwiftUI NavigationStack keeps the state of a screen whose place in the
// path stays, UIKit's setViewControllers keeps a screen passed again with its
// caller waiting, and Flutter's Navigator keeps the route, with its pending
// popped future, for a page of the same type at the same place.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('replaceAll keeps a screen below the top', () {
    // Steps: push PickerRoute with push<int>, push FirstRoute, replaceAll
    // with HomeRoute, PickerRoute and SecondRoute, go back to the picker with
    // system back, then tap an item.
    // Happened: the picker's screen was built anew, and the push answered
    // null at the replaceAll, so the item tapped went to no one.
    // Should: the picker keeps its screen, and the push gets the item.
    testWidgets('The caller of a picker kept below the top gets the item', (
      tester,
    ) async {
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => const TextPage('Home'),
          ),
          NamedRouteDef(
            name: 'PickerRoute',
            path: '/picker',
            builder: (context, _) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    const Text('Pick'),
                    for (final item in const [4, 5])
                      TextButton(
                        onPressed: () => context.router.maybePop(item),
                        child: Text('Item $item'),
                      ),
                  ],
                ),
              ),
            ),
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
        ],
      );
      await pumpRouterAppWithConfig(tester, router);
      var result = 'waiting';
      unawaited(
        router
            .push<int>(const NamedRoute('PickerRoute'))
            .then((value) => result = 'got ${value ?? 'null'}'),
      );
      await tester.pumpAndSettle();
      final pickerScreen = ModalRoute.of(tester.element(find.text('Pick')));
      unawaited(router.push(const NamedRoute('FirstRoute')));
      await tester.pumpAndSettle();

      unawaited(
        router.replaceAll(const [
          NamedRoute('HomeRoute'),
          NamedRoute('PickerRoute'),
          NamedRoute('SecondRoute'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      await expectBrowserUrl('/second');
      final atReplaceAll = result;

      await systemBack(tester);
      expect(
        ModalRoute.of(tester.element(find.text('Pick'))),
        same(pickerScreen),
      );
      await expectBrowserUrl('/picker');
      expect((atReplaceAll, result), ('waiting', 'waiting'));

      await tester.tap(find.text('Item 5'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await expectBrowserUrl('/');
      expect(result, 'got 5');
    });
  });
}
