import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Two pages of one route in a stack, such as /item/1 under /item/2, each
// hear only their own AutoRouteAware events.
// Steps: Home, push Item 1, push Item 2, both pages subscribed with
// AutoRouteAwareStateMixin; then pop Item 2, or push a third page over it.
// Before the fix, AutoRouteObserver keyed its subscribers by the route's key,
// which is the route name unless the route uses its path as key, so both
// pages heard every event of either: on the pop, Item 1 heard didPop and
// Item 2 didPopNext.
// Native behavior this holds to: each screen of a stack is its own, even when
// two show the same content. Flutter's RouteObserver keys its subscribers by
// the Route itself (widgets/routes.dart), and on iOS and Android each view
// controller or activity instance in a stack gets its own appear and
// disappear calls.
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
  Widget build(BuildContext context) =>
      Scaffold(body: Text('Item ${widget.id}'));

  @override
  void didPush() => _events.add('Item ${widget.id}.didPush');

  @override
  void didPop() => _events.add('Item ${widget.id}.didPop');

  @override
  void didPushNext() => _events.add('Item ${widget.id}.didPushNext');

  @override
  void didPopNext() => _events.add('Item ${widget.id}.didPopNext');
}

void main() {
  testWidgets(
    'Popping a page over another page of the same route tells each page only '
    'its own event',
    (tester) async {
      final router = RootStackRouter.build(
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
        ],
      );
      _events.clear();
      await pumpRouterConfigApp(
        tester,
        router.config(navigatorObservers: () => [AutoRouteObserver()]),
      );

      unawaited(
        router.push(const NamedRoute('ItemRoute', params: {'id': '1'})),
      );
      await tester.pumpAndSettle();
      unawaited(
        router.push(const NamedRoute('ItemRoute', params: {'id': '2'})),
      );
      await tester.pumpAndSettle();
      expect(router.stack.map((page) => page.routeData.match), [
        '/',
        '/item/1',
        '/item/2',
      ]);
      expect(_events, [
        'Item 1.didPush',
        'Item 1.didPushNext',
        'Item 2.didPush',
      ]);

      _events.clear();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Item 1'), findsOneWidget);
      expect(_events, ['Item 2.didPop', 'Item 1.didPopNext']);
    },
  );

  testWidgets(
    'A page under another page of the same route hears didPushNext once, not '
    'again when a third page covers the second',
    (tester) async {
      final router = RootStackRouter.build(
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
      _events.clear();
      await pumpRouterConfigApp(
        tester,
        router.config(navigatorObservers: () => [AutoRouteObserver()]),
      );
      unawaited(
        router.push(const NamedRoute('ItemRoute', params: {'id': '1'})),
      );
      await tester.pumpAndSettle();
      unawaited(
        router.push(const NamedRoute('ItemRoute', params: {'id': '2'})),
      );
      await tester.pumpAndSettle();

      _events.clear();
      unawaited(router.push(const NamedRoute('OtherRoute')));
      await tester.pumpAndSettle();
      expect(_events, ['Item 2.didPushNext']);
    },
  );
}
