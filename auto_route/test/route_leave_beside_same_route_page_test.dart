import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A screen that closes hears its AutoRouteLeaveListener even when a new page
// of its route goes on in the same step and takes over another screen of that
// route. Steps: Home, push /item/1, push /item/2, each item in a leave
// listener; then replaceAll([Home, Item 3]) or pushAndPopUntil(Item 3) to the
// first page. Item 3 takes over the screen of item 1, and the screen of item 2
// closes. With a page of another route under the items, Item 3 takes over
// the screen of item 2 instead, and the screen of item 1 closes. Before, every
// page that left was skipped when a new page shared its route, so the screen
// that closed was never told.
//
// Native behavior this holds to: Flutter's Navigator tells each route that
// leaves on its own (didPop, didComplete), whatever other routes show, and
// keeps the route of an old page only for the one new page it pairs with it
// (Page.canUpdate, from the bottom, then from the top, then by key). On iOS
// each view controller taken off the stack gets its own viewDidDisappear, on
// Android each activity its own onDestroy.
void main() {
  late List<String> leaves;
  late RootStackRouter router;

  setUp(() {
    leaves = [];
    router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('Home'),
        ),
        NamedRouteDef(
          name: 'ItemRoute',
          path: '/item/:id',
          builder: (_, data) =>
              _ItemPage(data.params.getString('id'), onLeave: leaves.add),
        ),
        NamedRouteDef(
          name: 'OtherRoute',
          path: '/other',
          builder: (_, _) => const Text('Other'),
        ),
      ],
    );
  });

  NamedRoute item(String id) => .new('ItemRoute', params: {'id': id});

  Future<void> open(WidgetTester tester, List<PageRouteInfo> routes) async {
    await pumpRouterApp(tester, router);
    for (final route in routes) {
      unawaited(router.push(route));
      await tester.pumpAndSettle();
    }
    leaves.clear();
  }

  // The screen, named by the item it was opened with, that shows item 3.
  String screenOfItem3(WidgetTester tester) =>
      tester.state<_ItemPageState>(find.byType(_ItemPage)).screen;

  testWidgets('replaceAll with one item: the screen that closes hears '
      'replaced, the one item 3 takes over hears nothing', (tester) async {
    await open(tester, [item('1'), item('2')]);
    unawaited(router.replaceAll([const NamedRoute('HomeRoute'), item('3')]));
    await tester.pumpAndSettle();
    expect(
      (screenOfItem3(tester), leaves.join(', ')),
      ('1', 'Item 2 replaced'),
    );
  });

  testWidgets('pushAndPopUntil with a new item: the screen that closes hears '
      'replaced, the one item 3 takes over hears nothing', (tester) async {
    await open(tester, [item('1'), item('2')]);
    unawaited(
      router.pushAndPopUntil(item('3'), predicate: (route) => route.isFirst),
    );
    await tester.pumpAndSettle();
    expect(
      (screenOfItem3(tester), leaves.join(', ')),
      ('1', 'Item 2 replaced'),
    );
  });

  testWidgets('A new top item takes over the top screen: the item under it '
      'hears replaced', (tester) async {
    await open(tester, [const NamedRoute('OtherRoute'), item('1'), item('2')]);
    unawaited(router.replaceAll([const NamedRoute('HomeRoute'), item('3')]));
    await tester.pumpAndSettle();
    expect(
      (screenOfItem3(tester), leaves.join(', ')),
      ('2', 'Item 1 replaced'),
    );
  });

  testWidgets('Without a new item, both items hear they left', (tester) async {
    await open(tester, [item('1'), item('2')]);
    unawaited(
      router.replaceAll([
        const NamedRoute('HomeRoute'),
        const NamedRoute('OtherRoute'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(leaves, ['Item 2 replaced', 'Item 1 replaced']);
  });
}

class _ItemPage extends StatefulWidget {
  const new(this.id, {required this.onLeave});

  final String id;
  final ValueChanged<String> onLeave;

  @override
  State<_ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<_ItemPage> {
  // The id the screen was opened with: a screen a new page takes over keeps
  // its State, so this names the screen, not the page it shows now.
  late final String screen;

  @override
  void initState() {
    super.initState();
    screen = widget.id;
  }

  @override
  Widget build(BuildContext context) => AutoRouteLeaveListener(
    onLeave: (kind) => widget.onLeave('Item $screen ${kind.name}'),
    child: Text('Item ${widget.id}'),
  );
}
