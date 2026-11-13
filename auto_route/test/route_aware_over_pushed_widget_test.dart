import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A page pushed over a page opened with pushWidget hears didPop when it is
// popped.
// Steps: Home, open a plain page with pushWidget, push Details, which
// subscribes with AutoRouteAwareStateMixin; pop Details, then the plain page.
// Before the fix Details heard didPush and never didPop: AutoRouteObserver
// told the page that leaves only when the route under it was a page of the
// router too, and a page opened with pushWidget is not.
// Native behavior this holds to: on iOS and Android a screen that leaves is
// always told it disappears, whatever shows under it; Flutter's
// RouteObserver<PageRoute>, the setup its doc shows, tells it here too,
// since a page opened with pushWidget is a PageRoute (widgets/routes.dart).
final _events = <String>[];

class _AwarePage extends StatefulWidget {
  const new(this.name);

  final String name;

  @override
  State<_AwarePage> createState() => _AwarePageState();
}

class _AwarePageState extends State<_AwarePage>
    with AutoRouteAwareStateMixin<_AwarePage> {
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(widget.name));

  @override
  void didPush() => _events.add('${widget.name}.didPush');

  @override
  void didPop() => _events.add('${widget.name}.didPop');

  @override
  void didPushNext() => _events.add('${widget.name}.didPushNext');

  @override
  void didPopNext() => _events.add('${widget.name}.didPopNext');
}

void main() {
  testWidgets('A page pushed over a page opened with pushWidget hears didPop '
      'when popped', (tester) async {
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const _AwarePage('Home'),
        ),
        NamedRouteDef(
          name: 'DetailsRoute',
          path: '/details',
          builder: (_, _) => const _AwarePage('Details'),
        ),
      ],
    );
    _events.clear();
    await pumpRouterConfigApp(
      tester,
      router.config(navigatorObservers: () => [AutoRouteObserver()]),
    );
    unawaited(router.pushWidget<void>(const Scaffold(body: Text('Plain'))));
    await tester.pumpAndSettle();
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Plain'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(_events, ['Home.didPush', 'Details.didPush', 'Details.didPop']);
  });
}
