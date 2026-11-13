import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// The default AutoTabsRouter takes a new duration when the app rebuilds it
// with one, as Flutter's animated widgets do.
// Headless test: auto_route/test/nested_tabs_router/tabs_duration_update_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('tabs duration update', () {
    // Steps: build the tabs with a duration of 300 ms and rebuild them with a
    // zero duration. Then change the tab.
    // Was: the new tab still faded in over 300 ms.
    // Should: it shows at once.
    testWidgets('Tabs rebuilt with a zero duration change without a fade', (
      tester,
    ) async {
      final duration = ValueNotifier(const Duration(milliseconds: 300));
      addTearDown(duration.dispose);
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => Scaffold(
              body: ValueListenableBuilder(
                valueListenable: duration,
                builder: (_, value, _) => AutoTabsRouter(
                  routes: const [NamedRoute('TabA'), NamedRoute('TabB')],
                  duration: value,
                ),
              ),
            ),
            children: [
              for (final name in ['TabA', 'TabB'])
                NamedRouteDef(
                  name: name,
                  path: name.substring(3).toLowerCase(),
                  builder: (_, _) => Center(child: Text(name)),
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpRouterApp(tester, router);

      duration.value = .zero;
      await tester.pumpAndSettle();
      router.innerRouterOf<TabsRouter>('HomeRoute')!.setActiveIndex(1);
      await tester.pump();

      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('TabB'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
      await tester.pumpAndSettle();
    });
  });
}
