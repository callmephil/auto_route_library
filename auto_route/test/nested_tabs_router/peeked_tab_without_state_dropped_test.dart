import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../router_test_utils.dart';

// A tab whose route doesn't maintain its state, which a drag only peeked
// at, is disposed once the view settles back on the tab it left.
// Steps: AutoTabsRouter.pageView or .tabBar with the tabs HomeTab and
// LiveTab. LiveTab keeps no state (maintainState is false), as the README
// suggests for a tab that opens a socket in initState. Drag HomeTab a
// quarter of the way toward LiveTab and let go.
// Was: the drag built LiveTab's page and it stayed built in the background
// until some later tab change: the views dropped such tabs only when the
// tabs router notified, and a drag that ends where it began changes no tab.
// Native behavior this holds to: the README says "the tab's page is
// disposed when another tab shows", and in Flutter's PageView a page that
// isn't kept alive is disposed once it is scrolled out of view.
void main() {
  for (final kind in _Tabs.values) {
    testWidgets(
      '${kind.name}: a tab that does not keep its state is dropped after a '
      'peek',
      (tester) => _expectPeekedTabDropped(tester, kind),
    );
  }
}

Future<void> _expectPeekedTabDropped(WidgetTester tester, _Tabs kind) async {
  const routes = [
    NamedRoute<Object?>('HomeTab'),
    NamedRoute<Object?>('LiveTab'),
  ];
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => Scaffold(
          body: switch (kind) {
            .pageView => const AutoTabsRouter.pageView(routes: routes),
            .tabBar => const AutoTabsRouter.tabBar(routes: routes),
          },
        ),
        children: [
          NamedRouteDef(
            name: 'HomeTab',
            path: 'home',
            builder: (_, _) => const _CountedPage('HomeTab'),
          ),
          NamedRouteDef(
            name: 'LiveTab',
            path: 'live',
            maintainState: false,
            builder: (_, _) => const _CountedPage('LiveTab'),
          ),
        ],
      ),
    ],
  );
  await pumpRouterApp(tester, router);
  // Cleared here, not in a setUp: the pages of the test before are
  // disposed when this one pumps its app.
  _initCounts.clear();
  _disposeCounts.clear();
  final tabs = router.innerRouterOf<TabsRouter>('HomeRoute')!;

  final gesture = await tester.startGesture(
    tester.getCenter(find.text('HomeTab')),
  );
  await gesture.moveBy(const Offset(-100, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(-100, 0));
  await tester.pump();
  expect(_initCounts['LiveTab'], 1);
  await gesture.up();
  await tester.pumpAndSettle();

  expect(tabs.activeIndex, 0);
  expect(find.text('HomeTab').hitTestable(), findsOneWidget);
  expect(_disposeCounts['LiveTab'], 1);
}

enum _Tabs { pageView, tabBar }

// How often each tab's page state was created and disposed.
final _initCounts = <String, int>{};
final _disposeCounts = <String, int>{};

class _CountedPage extends StatefulWidget {
  const new(this.name);

  final String name;

  @override
  State<_CountedPage> createState() => _CountedPageState();
}

class _CountedPageState extends State<_CountedPage> {
  @override
  void initState() {
    super.initState();
    _initCounts[widget.name] = (_initCounts[widget.name] ?? 0) + 1;
  }

  @override
  void dispose() {
    _disposeCounts[widget.name] = (_disposeCounts[widget.name] ?? 0) + 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.name));
}
