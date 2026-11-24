// Off the web only: on the web, back() is the browser's own back step.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// Off the web, back() into another tab asks only the guards of that tab, as
// the app's own tab change does, and no guard of a page that is still open
// (callmephil/auto_route_library#42).
//
// Steps: on Home, push /store/orders, push 7 in the router of the Orders
// tab, select Account, then call back(). Every stack route has the global
// guard, Store and Order have their own, and the Orders tab has a guard that
// waits 0 ms or 1 ms.
// Was: back() asked the guards of Store, of the tab, then of Order 7, the
// global guard of each page included. A slow guard of an open page kept
// Account on screen, and one that now said no kept back() there.
// Should: back() asks only the guard of the tab, as setActiveIndex(1) does
// and as the browser's back button does on the web
// (test/browser_back_to_open_page_asks_no_guard_test.dart). A page the step
// reaches as it was not is asked as before.
//
// Native behavior this holds to: Flutter's Navigator.pop asks nothing of the
// route under it, which gets only didPopNext. UITabBarController shows the
// stack of the selected tab as it is, and Android's back runs no check of
// the destination that shows again.

enum _Answer { yes, waits, no }

// Each guard notes its route in [asked], the global guard as 'global' and
// the route. [answer] is how the own guards of Store and Order answer.
class _StoreRouter extends RootStackRouter {
  new({required this.tabGuardWait});

  final Duration tabGuardWait;

  final asked = <String>[];

  _Answer answer = .yes;

  @override
  late final List<AutoRouteGuard> guards = [
    AutoRouteGuard.simple((resolver, _) {
      asked.add('global ${resolver.routeName}');
      resolver.next();
    }),
  ];

  AutoRouteGuard _noting(String name) => .simple((resolver, _) {
    asked.add(name);
    switch (answer) {
      case .yes:
        resolver.next();
      case .no:
        resolver.reject();
      case .waits:
        break;
    }
  });

  NamedRouteDef _page(String name, String path, {bool isGuarded = false}) =>
      .new(
        name: name,
        path: path,
        guards: [if (isGuarded) _noting(name)],
        builder: (_, _) => Text(name),
      );

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      guards: [_noting('Store')],
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [
            NamedRoute<Object?>('Shop'),
            NamedRoute<Object?>('Orders'),
            NamedRoute<Object?>('Account'),
          ],
        ),
      ),
      children: [
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          guards: [
            AutoRouteGuard.simple((resolver, _) async {
              asked.add('Orders');
              if (tabGuardWait > .zero) {
                await Future<void>.delayed(tabGuardWait);
              }
              resolver.next();
            }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [
            _page('OrdersIndex', ''),
            _page('Order', ':id', isGuarded: true),
          ],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

class _App {
  new(this.tester, {Duration tabGuardWait = .zero})
    : router = _StoreRouter(tabGuardWait: tabGuardWait);

  final WidgetTester tester;
  final _StoreRouter router;

  TabsRouter get tabs => router.innerRouterOf('Store')!;

  StackRouter get orders => tabs.innerRouterOf('Orders')!;

  String get shown => '${router.topRoute.name} ${router.currentUrl}';

  // With [moves], the app moves the page of Order 7 to Order 8 before
  // Account.
  Future<void> openAccountAfterOrder({bool moves = false}) async {
    await pumpRouterConfigApp(tester, router.config());
    unawaited(router.pushPath<Object?>('/store/orders'));
    await tester.pumpAndSettle();
    unawaited(orders.pushPath<Object?>('7'));
    await tester.pumpAndSettle();
    if (moves) {
      unawaited(orders.navigate(const NamedRoute('Order', params: {'id': 8})));
      await tester.pumpAndSettle();
    }
    tabs.setActiveIndex(2);
    await tester.pumpAndSettle();
    expect(shown, 'Account /store/account');
  }

  // The page shown after [step], and the routes whose guards [step] asked.
  Future<(String, String)> after(VoidCallback step) async {
    router.asked.clear();
    step();
    await tester.pumpAndSettle();
    final asked = router.asked;
    return (shown, asked.isEmpty ? 'no guard' : asked.join(', '));
  }
}

enum _Step { none, setActiveIndex, back }

// The session that the router asks its guards again for.
class _Session extends ChangeNotifier {
  bool isSignedIn = true;

  // A slow check of the session, which the guard of Order waits for.
  Completer<void>? check;

  int orderAsks = 0;

  void signOut() {
    isSignedIn = false;
    notifyListeners();
  }
}

// Home, and Store with the tabs Shop, Orders and Account. Orders holds
// OrdersIndex and Order, whose guard waits for the check of [session].
RootStackRouter _sessionRouter(_Session session) {
  NamedRouteDef page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));
  return .build(
    routes: [
      page('Home', '/'),
      NamedRouteDef(
        name: 'Store',
        path: '/store',
        builder: (_, _) => const Scaffold(
          body: AutoTabsRouter(
            routes: [
              NamedRoute<Object?>('Shop'),
              NamedRoute<Object?>('Orders'),
              NamedRoute<Object?>('Account'),
            ],
          ),
        ),
        children: [
          page('Shop', 'shop'),
          NamedRouteDef(
            name: 'Orders',
            path: 'orders',
            builder: (_, _) => const AutoRouter(),
            children: [
              page('OrdersIndex', ''),
              NamedRouteDef(
                name: 'Order',
                path: ':id',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    session.orderAsks++;
                    if (session.check case final check?) await check.future;
                    session.isSignedIn ? resolver.next() : resolver.reject();
                  }),
                ],
                builder: (_, _) => const Text('Order'),
              ),
            ],
          ),
          page('Account', 'account'),
        ],
      ),
    ],
  );
}

void main() {
  for (final tabGuardWait in [Duration.zero, const Duration(milliseconds: 1)]) {
    testWidgets('With a guard of the Orders tab that waits $tabGuardWait, '
        'back() into Orders shows Order 7 and asks only the guard of the tab, '
        'as setActiveIndex does', (tester) async {
      final app = _App(tester, tabGuardWait: tabGuardWait);
      await app.openAccountAfterOrder();

      final afterBack = await app.after(app.router.back);
      final historyAfterBack = app.router.navigationHistory.length;
      app.tabs.setActiveIndex(2);
      await tester.pumpAndSettle();
      final afterTabChange = await app.after(() => app.tabs.setActiveIndex(1));

      expect(tester.takeException(), isNull);
      expect(
        (afterBack, historyAfterBack, afterTabChange),
        (
          ('Order /store/orders/7', 'Orders'),
          3,
          ('Order /store/orders/7', 'Orders'),
        ),
      );
    });
  }

  // Was: the guard of Store was asked, and Account stayed on screen.
  for (final answer in [_Answer.waits, _Answer.no]) {
    testWidgets('back() into Orders shows Order 7 when the guards of the open '
        'pages ${answer.name == 'no' ? 'now say no' : 'wait'}', (tester) async {
      final app = _App(tester);
      await app.openAccountAfterOrder();
      app.router.answer = answer;

      expect(await app.after(app.router.back), (
        'Order /store/orders/7',
        'Orders',
      ));
    });
  }

  // Steps: as above, with Order 7 moved to Order 8, then back() twice.
  // Was: the second back() asked the guards of Store too.
  // Should: it asks those of Order, whose open page shows Order 8.
  testWidgets('back() to a page as it was not asks its guards', (tester) async {
    final app = _App(tester);
    await app.openAccountAfterOrder(moves: true);

    final afterSteps = [
      for (var step = 0; step < 2; step++) await app.after(app.router.back),
    ];

    expect(tester.takeException(), isNull);
    expect(afterSteps, [
      ('Order /store/orders/8', 'Orders'),
      ('Order /store/orders/7', 'global Order, Order'),
    ]);
  });

  // Steps: on Home, push /store/orders, push 7 in Orders, select Account. The
  // session check gets slow, and the user signs out: the reevaluation asks
  // the guard of Order 7, which waits for the check. The app calls back(),
  // or setActiveIndex(1), or neither. Then the check ends.
  // Was: after back(), the guard's no closed nothing. back() had put a new
  // page in place of Order 7, so the no came too late for the page it asked
  // about, and Order 7 stayed on screen for a signed-out user.
  // Should: the no closes Order 7 in each case, and back() asks no guard of
  // it. The pages list of a sign-out leaves the page out, and Flutter's
  // Navigator removes it: the latest change wins.
  for (final step in _Step.values) {
    testWidgets('A sign-out closes Order 7 while its guard decides, with '
        '${step.name} meanwhile', (tester) async {
      final session = _Session();
      addTearDown(session.dispose);
      final router = _sessionRouter(session);
      await pumpRouterApp(tester, router, reevaluationNotifier: session);
      unawaited(router.pushPath<Object?>('/store/orders'));
      await tester.pumpAndSettle();
      final tabs = router.innerRouterOf<TabsRouter>('Store')!;
      final orders = tabs.innerRouterOf<StackRouter>('Orders')!;
      unawaited(orders.pushPath<Object?>('7'));
      await tester.pumpAndSettle();
      tabs.setActiveIndex(2);
      await tester.pumpAndSettle();
      final check = Completer<void>();
      session
        ..check = check
        ..orderAsks = 0
        ..signOut();
      await tester.pumpAndSettle();
      switch (step) {
        case .none:
          break;
        case .setActiveIndex:
          tabs.setActiveIndex(1);
        case .back:
          router.back();
      }
      await tester.pumpAndSettle();
      final asks = session.orderAsks;
      check.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        (
          asks,
          router.currentUrl,
          orders.stack.map((page) => page.routeData.name).join(', '),
          find.text('Order').evaluate().length,
        ),
        (
          1,
          step == .none ? '/store/account' : '/store/orders',
          'OrdersIndex',
          0,
        ),
      );
    });
  }
}
