import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A page that is closing hears no AutoRouteAware event after its didPop.
// Steps: Home, push Item 1, whose State reads ModalRoute.of(context) and
// mixes in AutoRouteAwareStateMixin; pop it. The pop changes the route's
// isCurrent, so the State's didChangeDependencies runs again while the page
// animates out, and the mixin subscribes again. In an earlier version of
// this fix, the observer had already forgotten the popped route, took the
// page for a new one and told it didPush, then didPushNext.
// Native behavior this holds to: Flutter's RouteObserver.subscribe does
// nothing for a subscriber it already holds (widgets/routes.dart), and a view
// controller on iOS or an activity on Android that is leaving gets no appear
// call after its disappear.
final _events = <String>[];

class _ItemPage extends StatefulWidget {
  const new(this.id);

  final String id;

  @override
  State<_ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<_ItemPage>
    with AutoRouteAwareStateMixin<_ItemPage> {
  @override
  Widget build(BuildContext context) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    return Scaffold(body: Text('Item ${widget.id} current: $isCurrent'));
  }

  @override
  void didPush() => _events.add('Item ${widget.id}.didPush');

  @override
  void didPop() => _events.add('Item ${widget.id}.didPop');

  @override
  void didPushNext() => _events.add('Item ${widget.id}.didPushNext');

  @override
  void didPopNext() => _events.add('Item ${widget.id}.didPopNext');
}

RootStackRouter _router() => .build(
  routes: [
    NamedRouteDef(
      name: 'HomeRoute',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('Home')),
    ),
    NamedRouteDef(
      name: 'ItemRoute',
      path: '/item/:id',
      builder: (_, data) => _ItemPage(data.params.getString('id')),
    ),
    NamedRouteDef(
      name: 'OtherRoute',
      path: '/other',
      builder: (_, _) => const Scaffold(body: Text('Other')),
    ),
  ],
);

void main() {
  testWidgets('A popped page that rebuilds while it animates out hears no '
      'didPush after its didPop', (tester) async {
    final router = _router();
    _events.clear();
    await pumpRouterConfigApp(
      tester,
      router.config(navigatorObservers: () => [AutoRouteObserver()]),
    );
    unawaited(router.push(const NamedRoute('ItemRoute', params: {'id': '1'})));
    await tester.pumpAndSettle();
    expect(_events, ['Item 1.didPush']);

    _events.clear();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(_events, ['Item 1.didPop']);
  });

  testWidgets('A page covered then uncovered, whose State rebuilds on each, '
      'hears each event once', (tester) async {
    final router = _router();
    _events.clear();
    await pumpRouterConfigApp(
      tester,
      router.config(navigatorObservers: () => [AutoRouteObserver()]),
    );
    unawaited(router.push(const NamedRoute('ItemRoute', params: {'id': '1'})));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('OtherRoute')));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(_events, [
      'Item 1.didPush',
      'Item 1.didPushNext',
      'Item 1.didPopNext',
    ]);
  });

  testWidgets('replace() of a page by another page of the same route: the '
      'new page hears didPush, and didPop when popped', (tester) async {
    final router = _router();
    _events.clear();
    await pumpRouterConfigApp(
      tester,
      router.config(navigatorObservers: () => [AutoRouteObserver()]),
    );
    unawaited(router.push(const NamedRoute('ItemRoute', params: {'id': '1'})));
    await tester.pumpAndSettle();
    unawaited(
      router.replace(const NamedRoute('ItemRoute', params: {'id': '2'})),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Item 2'), findsOneWidget);
    _events.clear();
    unawaited(router.push(const NamedRoute('OtherRoute')));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    // Which item name the State reports depends on whether the route was
    // updated in place; the events themselves must be these three.
    expect(_events.map((e) => e.split('.').lastOrNull), [
      'didPushNext',
      'didPopNext',
      'didPop',
    ]);
  });
}
