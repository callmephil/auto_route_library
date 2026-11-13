import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// The default AutoTabsRouter, and AutoTabsScaffold's animationDuration, take
// a new duration and curve when the app rebuilds them with one.
// Steps: build AutoTabsRouter with 300 ms, rebuild it with Duration.zero, as
// an app does that follows the system's "remove animations" setting, then
// change the tab.
// Was: the tab still faded in over 300 ms: the duration and curve were read
// once, when the tabs were first built.
// Native behavior this holds to: Flutter's ImplicitlyAnimatedWidgetState
// sets the new duration on its controller in didUpdateWidget, and
// DefaultTabController rebuilds its controller when animationDuration
// changes. The second test, built with a zero duration, is a control.
void main() {
  for (final (label, first) in [
    ('rebuilt with a zero duration', const Duration(milliseconds: 300)),
    ('built with a zero duration', Duration.zero),
  ]) {
    testWidgets('$label: the next tab change does not fade', (tester) async {
      final duration = ValueNotifier(first);
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
      await pumpRouterApp(tester, router);

      duration.value = .zero;
      await tester.pumpAndSettle();
      router.innerRouterOf<TabsRouter>('HomeRoute')!.setActiveIndex(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

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
  }
}
