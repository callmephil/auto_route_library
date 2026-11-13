import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// In AutoTabsRouter.pageView, a second tab change while the first still
// moves shows only the tab left, the first tab chosen and the second, then
// rests on the second.
// Steps: the five tabs TabA to TabE, every page built at once. Starting on
// TabA, choose one tab and then another at once or 100 ms later, as two
// quick taps on a bottom bar do. Every 8 ms, note which tabs are on screen.
// Was: a tab neither left nor chosen showed during the move, such as TabD
// for TabE then TabC. A move of more than one page swaps the tab left next
// to the tab chosen; the second change put the pages back in the tabs'
// order while the view sat on the swapped page, so that page showed another
// tab, and the end of the cut-off move put them back again under the new
// one.
// Native behavior this holds to: UITabBarController and Android's
// BottomNavigationView show only the tab selected; the tabs between are
// never shown.
void main() {
  for (final (first, second) in [
    ('TabE', 'TabC'),
    ('TabE', 'TabB'),
    ('TabC', 'TabE'),
    ('TabE', 'TabA'),
    ('TabB', 'TabD'),
  ]) {
    for (final gap in const [Duration.zero, Duration(milliseconds: 100)]) {
      testWidgets(
        '$first then $second after ${gap.inMilliseconds} ms shows no other '
        'tab',
        (tester) => _expectOnlyChosenTabs(tester, first, second, gap),
      );
    }
  }
}

Future<void> _expectOnlyChosenTabs(
  WidgetTester tester,
  String first,
  String second,
  Duration gap,
) async {
  final router = _buildRouter();
  await pumpRouterApp(tester, router);
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;
  final seen = <String>{};
  Future<void> watch(Duration span) async {
    for (var t = Duration.zero; t < span; t += _kFrame) {
      await tester.pump(_kFrame);
      seen.addAll(_onScreen(tester));
    }
  }

  tabs.setActiveIndex(_kTabNames.indexOf(first));
  await tester.pump();
  await watch(gap);
  tabs.setActiveIndex(_kTabNames.indexOf(second));
  await watch(const Duration(milliseconds: 640));
  await tester.pumpAndSettle();

  expect(seen.difference({'TabA', first, second}), isEmpty);
  expect(_onScreen(tester), {second});
}

const _kTabNames = ['TabA', 'TabB', 'TabC', 'TabD', 'TabE'];

const _kFrame = Duration(milliseconds: 8);

// The tabs whose text has its center on screen.
Set<String> _onScreen(WidgetTester tester) {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return {
    for (final name in _kTabNames)
      for (final element in find.text(name, skipOffstage: false).evaluate())
        if (element.renderObject case final RenderBox box
            when box.attached && box.hasSize)
          if (box.localToGlobal(box.size.center(.zero)).dx case final dx
              when dx >= 0 && dx <= width)
            name,
  };
}

RootStackRouter _buildRouter() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => Scaffold(
        body: AutoTabsRouter.pageView(
          routes: [for (final name in _kTabNames) NamedRoute<Object?>(name)],
          lazyLoad: false,
        ),
      ),
      children: [
        for (final name in _kTabNames)
          NamedRouteDef(
            name: name,
            path: name.substring(3).toLowerCase(),
            builder: (_, _) => Center(child: Text(name)),
          ),
      ],
    ),
  ],
);
