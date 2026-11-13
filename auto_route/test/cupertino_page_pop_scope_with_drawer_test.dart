import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageRoute;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'back_test_utils.dart';
import 'router_test_utils.dart';

// On a Cupertino page (RouteType.cupertino, or RouteType.adaptive on iOS and
// macOS), back didn't ask the page's PopScope(canPop: false) while the page
// had a local history entry, such as an open drawer: back closed the drawer
// and the PopScope heard nothing. On a Material page of the same app the
// PopScope was asked and the drawer stayed. Found by the audit of
// auto_route/lib at dev 56b73492 (finding W16).
// Cause: CupertinoRouteTransitionOverrideMixin.popDisposition answered `pop`
// whenever the route willHandlePopInternally, before ModalRoute looked at its
// PopScopes. Upstream added it in b637300d (2023-12-07, "fix some
// deprecations") with no reason given.
// Steps: push a page wrapped in PopScope(canPop: false) whose Scaffold has a
// drawer, open the drawer, press system back.
// Should: the PopScope is told of the refused pop and the drawer stays, as
// with Flutter's own CupertinoPageRoute and MaterialPageRoute, where
// ModalRoute.popDisposition asks the PopScopes first and its local history
// second (widgets/routes.dart, ModalRoute.popDisposition and
// LocalHistoryRoute.popDisposition); the controls below hold both, and the
// fork's Material page. The app hears the refused back and can close the
// drawer itself.
final _heard = <String>[];

Widget _guardedDrawerPage() => PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) => _heard.add('didPop: $didPop'),
  child: Scaffold(
    appBar: AppBar(),
    drawer: const Drawer(child: Text('Drawer')),
    body: const Text('Guarded'),
  ),
);

Future<void> _openDrawerAndPressBack(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).last).openDrawer();
  await tester.pumpAndSettle();
  expect(find.text('Drawer'), findsOneWidget);
  _heard.clear();
  await systemBack(tester);
}

Future<void> _pumpAutoRoute(WidgetTester tester, RouteType type) async {
  final router = RootStackRouter.build(
    defaultRouteType: type,
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      NamedRouteDef(
        name: 'GuardedRoute',
        path: '/guarded',
        builder: (_, _) => _guardedDrawerPage(),
      ),
    ],
  );
  await pumpRouterConfigApp(tester, router.config());
  unawaited(router.push(const NamedRoute('GuardedRoute')));
  await tester.pumpAndSettle();
}

void main() {
  for (final isCupertino in [false, true]) {
    testWidgets(
      "Control: Flutter's ${isCupertino ? 'CupertinoPageRoute' : 'MaterialPageRoute'} "
      'asks the PopScope and keeps the drawer',
      (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Home')),
          ),
        );
        navigatorKey.currentState!.push<void>(
          isCupertino
              ? CupertinoPageRoute(builder: (_) => _guardedDrawerPage())
              : MaterialPageRoute(builder: (_) => _guardedDrawerPage()),
        );
        await tester.pumpAndSettle();
        await _openDrawerAndPressBack(tester);
        expect(_heard, ['didPop: false']);
        expect(find.text('Drawer'), findsOneWidget);
      },
    );
  }

  testWidgets('Control: a Material page asks the PopScope and keeps the '
      'drawer', (tester) async {
    await _pumpAutoRoute(tester, const RouteType.material());
    await _openDrawerAndPressBack(tester);
    expect(_heard, ['didPop: false']);
    expect(find.text('Drawer'), findsOneWidget);
  });

  testWidgets('A Cupertino page asks the PopScope and keeps the drawer', (
    tester,
  ) async {
    await _pumpAutoRoute(tester, const RouteType.cupertino());
    await _openDrawerAndPressBack(tester);
    expect(_heard, ['didPop: false']);
    expect(find.text('Drawer'), findsOneWidget);
  });
}
