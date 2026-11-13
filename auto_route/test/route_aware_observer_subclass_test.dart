import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Pages under an app's own subclass of AutoRouteObserver that overrides
// didPush without calling super still hear didPop and didPopNext.
// Steps: an observer that only logs in didPush; Home, push Details, pop.
// In an earlier version of this fix, the observer learned its routes in
// didPush, so with that override it found no route for any page and told no
// page of the pop.
// Native behavior this holds to: a subclass of Flutter's RouteObserver that
// overrides didPush without super loses only what didPush sends,
// didPushNext; subscribe files a page under its own route
// (widgets/routes.dart).
final _events = <String>[];

class _LoggingObserver extends AutoRouteObserver {
  final pushed = <String>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    pushed.add(route.settings.name ?? '');
  }
}

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
  testWidgets('Pages under a subclass that overrides didPush without super '
      'still hear didPop and didPopNext', (tester) async {
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
      router.config(navigatorObservers: () => [_LoggingObserver()]),
    );
    unawaited(router.push(const NamedRoute('DetailsRoute')));
    await tester.pumpAndSettle();
    _events.clear();
    router.pop();
    await tester.pumpAndSettle();
    expect(_events, ['Details.didPop', 'Home.didPopNext']);
  });
}
