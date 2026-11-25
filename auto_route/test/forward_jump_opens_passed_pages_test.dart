import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/router/controller/navigation_history/browser/browser_navigation_history.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'history_test_browser.dart';
import 'router_test_utils.dart';

// On the web, a jump forward over several entries opens the page of each
// entry it passes, in order, as forward presses do, and changes no entry
// (callmephil/auto_route_library#41). The list a long press on the forward
// button shows makes such a jump, and so does history.go(2).
//
// Steps: on Home, push A and then B. Press the browser's back button two
// times and jump two entries forward, onto B. Or on Home, open Store on
// Orders and Order 7 in Orders, and then select Account. Press back three
// times, which closes Store, and jump three entries forward onto Account
// or two onto Order 7.
// Was: the app opened only the page of the entry landed on, over Home. It
// stepped the browser back to the entry of Home and pushed that url, which
// dropped the entries between and ahead, so back then showed Home.
// Should: the stack and the entries are what as many forward presses give.
// The app asks the browser for no write and no step, and back then shows
// the pages of the entries passed. A guard that says no to a passed entry
// ends the jump there, as it ends a forward press onto that entry.
//
// Native behavior this holds to: the HTML standard's session history, where
// history.go(n) goes to the entry n steps away, adds no entry and changes
// none. The back button then goes to the entry before.
//
// The same walk runs in a real browser in test/web/forward_jump_web_test.dart
// and in the example app in
// example.old/integration_test/forward_jump_opens_passed_pages_test.dart.

// The app of the issue: Home, A, B and Item, then Store with the tabs
// Shop, Orders and Account; Orders holds a nested router with OrdersIndex
// and Order. With [ordersWait], the guard of Orders waits that long, as the
// sign-in check of callmephil/auto_route_library#31 does. The guard of A
// shows Login until the wait [signingIn] gives ends, and then lets A in
// while [allowsA] says so, with the query [signInQuery] gives after a
// sign-in. B and Login refuse a pop while [bRefusesPop] and
// [loginRefusesPop] say so.
class _Router extends RootStackRouter {
  new(
    this._browser, {
    required this.allowsA,
    required this.signingIn,
    required this.signInQuery,
    required this.bRefusesPop,
    required this.loginRefusesPop,
    this.ordersWait,
  });

  final TestHistoryBrowser _browser;
  final bool Function() allowsA;
  final Completer<void>? Function() signingIn;
  final Map<String, String>? Function() signInQuery;
  final bool Function() bRefusesPop;
  final bool Function() loginRefusesPop;
  final Duration? ordersWait;

  @override
  late final NavigationHistory navigationHistory = BrowserNavigationHistory(
    this,
    _browser,
    // The test's clock runs through every animation at once; the browser
    // of a test lands late, never too late.
    landingLimit: const Duration(hours: 1),
  );

  NamedRouteDef _page(String name, String path) =>
      .new(name: name, path: path, builder: (_, _) => Text(name));

  @override
  late final List<AutoRoute> routes = [
    _page('Home', '/'),
    NamedRouteDef(
      name: 'A',
      path: '/a',
      guards: [
        AutoRouteGuard.simple((resolver, _) async {
          final wait = signingIn();
          final signsIn = wait != null && !wait.isCompleted;
          if (signsIn) {
            unawaited(
              resolver.redirectUntil(const NamedRoute<Object?>('Login')),
            );
            await wait.future;
          }
          final query = signsIn ? signInQuery() : null;
          if (!allowsA()) {
            resolver.reject();
          } else if (query != null) {
            resolver.overrideNext(queryParams: query);
          } else {
            resolver.next();
          }
        }),
      ],
      builder: (_, _) => const Text('A'),
    ),
    NamedRouteDef(
      name: 'B',
      path: '/b',
      builder: (_, _) =>
          PopScope(canPop: !bRefusesPop(), child: const Text('B')),
    ),
    _page('C', '/c'),
    _page('D', '/d'),
    _page('Item', '/item'),
    NamedRouteDef(
      name: 'Login',
      path: '/login',
      builder: (_, _) =>
          PopScope(canPop: !loginRefusesPop(), child: const Text('Login')),
    ),
    _page('Register', '/register'),
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
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          guards: [
            if (ordersWait case final wait?)
              AutoRouteGuard.simple((resolver, _) async {
                await Future<void>.delayed(wait);
                resolver.next();
              }),
          ],
          builder: (_, _) => const AutoRouter(),
          children: [_page('OrdersIndex', ''), _page('Order', ':id')],
        ),
        _page('Account', 'account'),
      ],
    ),
  ];
}

class _App {
  new(this.tester, {Duration? ordersWait}) {
    router = _Router(
      browser,
      allowsA: () => allowsA,
      signingIn: () => signingIn,
      signInQuery: () => signInQuery,
      bRefusesPop: () => bRefusesPop,
      loginRefusesPop: () => loginRefusesPop,
      ordersWait: ordersWait,
    );
    browser.reportLandingsTo(tester);
  }

  final WidgetTester tester;
  final browser = TestHistoryBrowser();
  late final _Router router;

  // Whether the guard of A lets it in.
  bool allowsA = true;

  // The user is signed out until it completes.
  Completer<void>? signingIn;

  Map<String, String>? signInQuery;

  // Whether a page B built from now on refuses a pop.
  bool bRefusesPop = false;

  bool loginRefusesPop = false;

  // The page on top, the url the browser shows, the pages of the root's
  // stack and of the router of Orders, and every entry of the browser.
  String get shown {
    String names(StackRouter? stack) =>
        stack?.stack.map((page) => page.routeData.name).join(' ') ?? '';
    final orders = router
        .innerRouterOf<TabsRouter>('Store')
        ?.innerRouterOf<StackRouter>('Orders');
    return '${router.topRoute.name} ${browser.url} [${names(router)}] '
        '[${names(orders)}] ${browser.held}';
  }

  Future<void> open({required bool prefix}) async {
    addTearDown(router.navigationHistory.dispose);
    await pumpRouterConfigApp(
      tester,
      router.config(includePrefixMatches: prefix),
    );
    await browser.settle(tester);
  }

  Future<void> push(String name) async {
    unawaited(router.push(NamedRoute<Object?>(name)));
    await browser.settle(tester);
  }

  // The page shown after each press of [press] until it has no entry to go
  // to, at most [limit] presses.
  Future<List<String>> walk(bool Function() press, int limit) async {
    final shownAfter = <String>[];
    for (var i = 0; i < limit && press(); i++) {
      await browser.settle(tester);
      shownAfter.add(shown);
    }
    return shownAfter;
  }

  // What the page shows after [move], and what the app asked of the browser
  // for it.
  Future<(String, String)> after(void Function() move) async {
    final asked = browser.asked.length;
    move();
    await browser.settle(tester);
    return (shown, browser.asked.skip(asked).join(', '));
  }

  Future<(String, String)> jump(int delta) =>
      after(() => expect(browser.didJump(delta), isTrue));

  Future<(String, String)> back() =>
      after(() => expect(browser.didPressBack(), isTrue));

  // The platform hands over a link to [location], as the engine does.
  Future<void> handOverLink(String location) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', {
            'location': location,
            'state': null,
          }),
        ),
        null,
      );
}

// The steps before the back presses, with the number of entries they leave
// ahead of Home.
typedef _Steps = Future<int> Function(_App app, {required bool prefix});

Future<int> _openB(_App app, {required bool prefix}) async {
  await app.open(prefix: prefix);
  await app.push('A');
  await app.push('B');
  return 2;
}

Future<int> _openABThenItem(_App app, {required bool prefix}) async {
  await _openB(app, prefix: prefix);
  await app.push('Item');
  return 3;
}

// Two pages with one url, which a forward press tells apart by its entry.
Future<int> _openTwoItemsThenA(_App app, {required bool prefix}) async {
  await app.open(prefix: prefix);
  await app.push('Item');
  await app.push('Item');
  await app.push('A');
  return 3;
}

Future<int> _openStateOfAThenB(_App app, {required bool prefix}) async {
  await app.open(prefix: prefix);
  await app.push('A');
  app.router.navigationHistory.pushPathState('picked');
  await app.browser.settle(app.tester);
  await app.push('B');
  return 3;
}

Future<int> _openAccountAfterOrder(_App app, {required bool prefix}) async {
  await app.open(prefix: prefix);
  unawaited(app.router.pushPath<Object?>('/store/orders'));
  await app.browser.settle(app.tester);
  final tabs = app.router.innerRouterOf<TabsRouter>('Store')!;
  unawaited(tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>('7'));
  await app.browser.settle(app.tester);
  tabs.setActiveIndex(2);
  await app.browser.settle(app.tester);
  return 3;
}

Future<int> _openAccountThenA(_App app, {required bool prefix}) async {
  await app.open(prefix: prefix);
  unawaited(app.router.pushPath<Object?>('/store/orders'));
  await app.browser.settle(app.tester);
  app.router.innerRouterOf<TabsRouter>('Store')!.setActiveIndex(2);
  await app.browser.settle(app.tester);
  await app.push('A');
  return 3;
}

Future<int> _openBItemThenA(_App app, {required bool prefix}) async {
  await app.open(prefix: prefix);
  for (final name in ['B', 'Item', 'A']) {
    await app.push(name);
  }
  return 3;
}

// The app of a test after [steps] and back presses down to Home.
Future<_App> _onHomeAfter(
  WidgetTester tester,
  _Steps steps, {
  bool prefix = false,
  Duration? ordersWait,
}) async {
  final app = _App(tester, ordersWait: ordersWait);
  final ahead = await steps(app, prefix: prefix);
  await app.walk(app.browser.didPressBack, ahead);
  expect(app.router.topRoute.name, 'Home');
  return app;
}

// The app reloaded on the entry of A, with the entries of Home, A, B, C and
// D from before the reload.
Future<_App> _reloadedOnA(WidgetTester tester) async {
  final app = _App(tester);
  app.browser.entries
    ..clear()
    ..addAll([
      for (final url in ['/', '/a', '/b', '/c', '/d']) (url, null),
    ]);
  app.browser.index = 1;
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/a';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  await app.open(prefix: false);
  expect(app.shown, 'A /a [A] [] / >/a /b /c /d');
  return app;
}

// Signed out on Login in place of A, after a jump of three entries onto Item
// or after one forward press onto A.
Future<_App> _onLoginAfter(
  WidgetTester tester, {
  required bool jumps,
  bool loginRefusesPop = false,
}) async {
  final app = await _onHomeAfter(tester, _openABThenItem);
  app
    ..signingIn = Completer<void>()
    ..loginRefusesPop = loginRefusesPop;
  final (shown, _) = await app.after(
    () => expect(
      jumps ? app.browser.didJump(3) : app.browser.didPressForward(),
      isTrue,
    ),
  );
  expect(
    shown,
    jumps
        ? 'Login /item [Home Login] [] / /a /b >/item'
        : 'Login /login [Home Login] [] / >/login /b /item',
  );
  return app;
}

const _onStoreHome = '>/ /store/orders /store/orders/7 /store/account';

// What the app shows in Store on the entry of [url], with [orders] in the
// router of Orders; the browser holds the four entries the steps made.
String _inStore(String top, String url, String orders) {
  const urls = ['/', '/store/orders', '/store/orders/7', '/store/account'];
  final held = [
    for (final entry in urls)
      if (entry == url) '>$entry' else entry,
  ];
  return '$top $url [Home Store] [$orders] ${held.join(' ')}';
}

void main() {
  // With and without prefix matches, the default off the web and on it.
  for (final prefix in [false, true]) {
    testWidgets('A jump onto B opens A, then B, and back shows A, then Home, '
        'prefix matches $prefix', (tester) async {
      final app = await _onHomeAfter(tester, _openB, prefix: prefix);

      expect(await app.jump(2), ('B /b [Home A B] [] / /a >/b', ''));
      expect(await app.walk(app.browser.didPressBack, 3), [
        'A /a [Home A] [] / >/a /b',
        'Home / [Home] [] >/ /a /b',
      ]);
    });
  }

  for (final ordersWait in [null, const Duration(milliseconds: 1)]) {
    final waits = ordersWait == null ? '' : ', with a tab guard that waits';
    testWidgets('A jump onto Account opens OrdersIndex, Order 7 and Account, '
        'and keeps the four entries$waits', (tester) async {
      final app = await _onHomeAfter(
        tester,
        _openAccountAfterOrder,
        ordersWait: ordersWait,
      );
      expect(app.browser.held, _onStoreHome);

      expect(await app.jump(3), (
        _inStore('Account', '/store/account', 'OrdersIndex Order'),
        '',
      ));
      expect(await app.walk(app.browser.didPressBack, 4), [
        _inStore('Order', '/store/orders/7', 'OrdersIndex Order'),
        _inStore('OrdersIndex', '/store/orders', 'OrdersIndex'),
        'Home / [Home] [] $_onStoreHome',
      ]);
    });
  }

  testWidgets('A jump onto Order 7 shows it over OrdersIndex, with the entry '
      'of Account ahead', (tester) async {
    final app = await _onHomeAfter(tester, _openAccountAfterOrder);

    expect(await app.jump(2), (
      _inStore('Order', '/store/orders/7', 'OrdersIndex Order'),
      '',
    ));
    expect(await app.walk(app.browser.didPressForward, 2), [
      _inStore('Account', '/store/account', 'OrdersIndex Order'),
    ]);
  });

  // The rule of the issue itself, on the neighbors too: two pages with one
  // url, an entry made by pushPathState, and a tab passed on the way to A.
  group('A jump ends as as many forward presses end:', () {
    for (final (label, steps) in [
      ('A and B', _openB),
      ('two Items with one url, then A', _openTwoItemsThenA),
      ('a pushPathState entry of A, then B', _openStateOfAThenB),
      ('Store', _openAccountAfterOrder),
      ('Store on Orders, then Account, then A over Store', _openAccountThenA),
    ]) {
      testWidgets(label, (tester) async {
        // The page landed on and each back press after it, by jump or by
        // forward presses; the jump asks the browser for nothing.
        final walks = <bool, List<String>>{};
        for (final jumps in [false, true]) {
          final app = await _onHomeAfter(tester, steps);
          final ahead = app.browser.entries.length - 1;
          final List<String> forward;
          if (jumps) {
            final (shown, asked) = await app.jump(ahead);
            expect(asked, isEmpty);
            forward = [shown];
          } else {
            forward = await app.walk(app.browser.didPressForward, ahead);
          }
          final back = await app.walk(app.browser.didPressBack, ahead);
          walks[jumps] = [?forward.lastOrNull, ...back];
          await tester.pumpWidget(const SizedBox());
        }
        expect(walks[true], walks[false]);
      });
    }
  });

  // Steps: the browser holds the entries of Home, A, B, C and D, and the app
  // reloads on A. Press forward two times and back two times. Jump three
  // entries forward onto D, which the app has not stood on since the reload.
  // Was: D over A; the app asked go -3 and push /d, which dropped B and C.
  // Should: what three forward presses give, and back shows C.
  // Native behavior this holds to: the HTML standard's session history, where
  // a traversal adds or changes no entry.
  for (final jumps in [true, false]) {
    testWidgets('After a reload, every entry stays after '
        '${jumps ? 'a jump' : 'forward presses'} onto an entry from before '
        'it', (tester) async {
      final app = await _reloadedOnA(tester);
      await app.walk(app.browser.didPressForward, 2);
      await app.walk(app.browser.didPressBack, 2);

      final onD = jumps
          ? await app.jump(3)
          : await app.after(() {
              for (var i = 0; i < 3; i++) {
                expect(app.browser.didPressForward(), isTrue);
              }
            });
      expect(onD, ('D /d [A B C D] [] / /a /b /c >/d', ''));
      expect(await app.back(), ('C /c [A B C] [] / /a /b >/c /d', ''));
    });
  }

  // Steps: on Home, push A, then B, and press back two times. The guard of A
  // now says no. Jump two entries forward.
  // Should: Home on its entry, with the entries of A and B ahead, as after
  // two forward presses onto A that its guard turns down.
  testWidgets('A guard that says no to a passed entry ends the jump on the '
      'page shown before', (tester) async {
    final app = await _onHomeAfter(tester, _openB);
    app.allowsA = false;

    expect(await app.jump(2), ('Home / [Home] [] >/ /a /b', 'go -2'));
  });

  // Steps: on Home, push A, B and Item, press back three times and sign
  // out. Jump three entries forward: the guard of A shows Login in its place.
  // Press back, and then back again or pop B.
  // Was: back showed B over Login, but the app stepped the browser back to
  // Home and pushed /login and /b, which dropped the entry of Item.
  // Should: back changes no entry. The entry of A keeps /a while the browser
  // stands beyond it; Login writes /login there once the browser is back on
  // it, as after a forward press onto A.
  // Native behavior this holds to: the HTML standard's session history, where
  // a back traversal changes no entry and history.replaceState writes only
  // the entry the browser stands on.
  group('While a passed entry shows its sign-in page,', () {
    Future<_App> onLogin(
      WidgetTester tester, {
      bool bRefusesPop = false,
    }) async {
      final app = await _onHomeAfter(tester, _openABThenItem);
      app
        ..signingIn = Completer<void>()
        ..bRefusesPop = bRefusesPop;
      expect(await app.jump(3), (
        'Login /item [Home Login] [] / /a /b >/item',
        '',
      ));
      return app;
    }

    const onB = 'B /b [Home Login B] [] / /a >/b /item';
    const onLoginEntry = 'Login /login [Home Login] [] / >/login /b /item';

    testWidgets('back keeps the entries ahead', (tester) async {
      final app = await onLogin(tester);

      expect(await app.back(), (onB, ''));
      expect(await app.back(), (onLoginEntry, 'replace /login'));
    });

    testWidgets('a pop over Login steps back one entry', (tester) async {
      final app = await onLogin(tester);
      await app.back();

      expect(await app.after(() => unawaited(app.router.maybePop())), (
        onLoginEntry,
        'go -1, replace /login',
      ));
    });

    testWidgets('a sign-in lets the jump go on', (tester) async {
      final app = await onLogin(tester);

      expect(await app.after(app.signingIn!.complete), (
        'Item /item [Home A B Item] [] / /a /b >/item',
        '',
      ));
    });

    // Steps: Register takes the place of Login, as a link to sign up does.
    // Press back two times. Was: B over Register, but the app asked go -2
    // and pushed /register and /b, which dropped the entry of Item.
    testWidgets('a page that replaces Login keeps the entries ahead', (
      tester,
    ) async {
      final app = await onLogin(tester);
      expect(
        await app.after(
          () => unawaited(
            app.router.replace(const NamedRoute<Object?>('Register')),
          ),
        ),
        ('Register /item [Home Register] [] / /a /b >/item', ''),
      );

      expect(await app.back(), (
        'B /b [Home Register B] [] / /a >/b /item',
        '',
      ));
      expect(await app.back(), (
        'Register /register [Home Register] [] / >/register /b /item',
        'replace /register',
      ));
    });

    // Steps: B refuses a pop. Press back onto B, then back again or jump
    // back onto Home. Was: the app wrote /login over the entry of A and
    // pushed /b, which dropped the entry of Item. Should: as after forward
    // presses, the browser goes back to the entry of B, Item ahead.
    // Native behavior this holds to: Flutter's Navigator, where a PopScope
    // with canPop false keeps its page.
    testWidgets('a back that B refuses keeps the entries ahead', (
      tester,
    ) async {
      final app = await onLogin(tester, bRefusesPop: true);
      expect(await app.back(), (onB, ''));

      expect(await app.back(), (
        'B /b [Home Login B] [] / /login >/b /item',
        'replace /login, go 1',
      ));
    });

    testWidgets('a jump back that B refuses keeps the entries ahead', (
      tester,
    ) async {
      final app = await onLogin(tester, bRefusesPop: true);
      await app.back();

      expect(await app.jump(-2), (onB, 'go 2'));
    });
  });

  // The control of a refused back: forward presses in place of the jump.
  testWidgets('After forward presses, a back that B refuses keeps the entries '
      'ahead', (tester) async {
    final app = await _onHomeAfter(tester, _openABThenItem);
    app
      ..signingIn = Completer<void>()
      ..bRefusesPop = true;
    await app.walk(app.browser.didPressForward, 3);
    await app.walk(app.browser.didPressBack, 1);

    expect(await app.back(), (
      'B /b [Home Login B] [] / /login >/b /item',
      'go 1',
    ));
  });

  // Steps: on Home, push A, B and Item, press back three times and sign out.
  // Jump two entries forward onto B: Login shows in place of A. Sign in: the
  // guard lets A in at /a?from=sign-in. Press back.
  // Was: the app asked go -2 and pushed /a?from=sign-in and /b, which dropped
  // the entry of Item. Should: B on its entry, and back writes the url of A
  // over the entry of A, as after forward presses.
  // Native behavior this holds to: the HTML standard's history.replaceState,
  // which writes only the entry the browser stands on.
  for (final jumps in [true, false]) {
    testWidgets('${jumps ? 'After a jump' : 'After forward presses'}, a '
        'sign-in that opens A at another url keeps the entry of Item ahead', (
      tester,
    ) async {
      final app = await _onHomeAfter(tester, _openABThenItem);
      app
        ..signingIn = Completer<void>()
        ..signInQuery = const {'from': 'sign-in'};
      if (jumps) {
        await app.jump(2);
        expect(await app.after(app.signingIn!.complete), (
          'B /b [Home A B] [] / /a >/b /item',
          '',
        ));
      } else {
        await app.walk(app.browser.didPressForward, 1);
        await app.after(app.signingIn!.complete);
        await app.walk(app.browser.didPressForward, 1);
      }

      expect(
        (await app.back()).$1,
        'A /a?from=sign-in [Home A] [] / >/a?from=sign-in /b /item',
      );
    });
  }

  String after(bool jumps) => jumps ? 'After a jump' : 'After a forward press';

  // Steps: on Home, push A, B and Item, press back three times and sign out.
  // Jump three entries forward, or press forward once: Login shows in place
  // of A. Login refuses a pop. Go back onto Home, three entries or one.
  // Was, after the jump: Login stayed, but the app asked nothing, so the
  // browser stood on the entry of Home: the jump still held the writes.
  // Should: the browser goes back to the entry of Login, as after the forward
  // press; the entry of A, owed /login, gets it there.
  // Native behavior this holds to: Flutter's Navigator, where a PopScope with
  // canPop false keeps its page, and the HTML standard's session history,
  // where history.replaceState writes only the entry the browser stands on.
  for (final jumps in [true, false]) {
    testWidgets('${after(jumps)}, a step back that Login refuses returns the '
        'browser to its entry', (tester) async {
      final app = await _onLoginAfter(
        tester,
        jumps: jumps,
        loginRefusesPop: true,
      );

      expect(await app.jump(jumps ? -3 : -1), (
        'Login /login [Home Login] [] / >/login /b /item',
        jumps ? 'go 1, replace /login' : 'go 1',
      ));
    });
  }

  // Steps: as before, with no PopScope on Login. The sign-in flow calls
  // popAndPush(Register), or removeLast and push in one turn. Press back.
  // Was, after the jump: the jump held the writes, so Register showed with
  // the browser on the entry of Item. Back then showed B over Register, and
  // the app asked go -2, push /register and push /b.
  // Should: as after the forward press, the step back and the push of
  // /register drop the entries ahead, and back shows Home.
  // Native behavior this holds to: Flutter's Navigator, where a popped page
  // stays closed, and the HTML standard's session history, where pushState
  // drops the entries ahead.
  for (final jumps in [true, false]) {
    for (final (label, signUp) in <(String, void Function(StackRouter))>[
      (
        'popAndPush',
        (router) =>
            unawaited(router.popAndPush(const NamedRoute<Object?>('Register'))),
      ),
      (
        'removeLast and push',
        (router) {
          router.removeLast();
          unawaited(router.push(const NamedRoute<Object?>('Register')));
        },
      ),
    ]) {
      testWidgets('${after(jumps)}, $label of Register over Login writes the '
          'browser', (tester) async {
        final app = await _onLoginAfter(tester, jumps: jumps);

        expect(await app.after(() => signUp(app.router)), (
          'Register /register [Home Register] [] / >/register',
          'go ${jumps ? -3 : -1}, push /register',
        ));
        expect(await app.back(), ('Home / [Home] [] >/ /register', ''));
      });
    }
  }

  // Steps: as before. Login calls router.back(), as a cancel button does, or
  // the app calls forward(). Was, after the jump: the jump held the step.
  // Should: the page and the entries of the forward press. The jump's step
  // goes from the entry of Login, which it writes first.
  // Native behavior this holds to: the HTML standard's history.go(n), which
  // goes n entries from the one the browser stands on.
  for (final jumps in [true, false]) {
    for (final (label, step, shown, asked) in [
      (
        'back()',
        (StackRouter router) => router.back(),
        'Home / [Home] [] >/ /login /b /item',
        'go -1',
      ),
      (
        'forward()',
        (StackRouter router) => router.navigationHistory.forward(),
        'B /b [Home Login B] [] / /login >/b /item',
        'go 1',
      ),
    ]) {
      testWidgets('${after(jumps)}, $label on Login steps from its entry', (
        tester,
      ) async {
        final app = await _onLoginAfter(tester, jumps: jumps);

        expect(await app.after(() => step(app.router)), (
          shown,
          jumps ? 'go -2, replace /login, $asked' : asked,
        ));
      });
    }
  }

  // Steps: as before. The app pops Login, or pushes Register over it.
  // Was, after the jump: the jump held the writes, and none was written.
  // Should: the page and the entries of the forward press, but the entry of
  // A keeps its url while the browser does not stand there.
  // Native behavior this holds to: the HTML standard's session history,
  // where a step back leaves the entries ahead and pushState drops them.
  for (final jumps in [true, false]) {
    final entryOfA = jumps ? '/a' : '/login';
    for (final (label, navigate, shown, asked) in [
      (
        'a pop of Login',
        (StackRouter router) => unawaited(router.maybePop()),
        'Home / [Home] [] >/ $entryOfA /b /item',
        jumps ? 'go -3' : 'go -1',
      ),
      (
        'a push over Login',
        (StackRouter router) =>
            unawaited(router.push(const NamedRoute<Object?>('Register'))),
        'Register /register [Home Login Register] [] / $entryOfA >/register',
        jumps ? 'go -2, push /register' : 'push /register',
      ),
    ]) {
      testWidgets('${after(jumps)}, $label writes the browser', (tester) async {
        final app = await _onLoginAfter(tester, jumps: jumps);

        expect(await app.after(() => navigate(app.router)), (shown, asked));
      });
    }
  }

  // Steps: as before, then the app calls pushPathState on Login, and the user
  // presses back.
  // Was, after the jump: the jump held the new entry, and none was written.
  // Should: a new entry after the entry of Login, as the forward press gives.
  // Back then shows Login. The entry of A gets the url of Login when the
  // browser stands there.
  // Native behavior this holds to: the HTML standard's history.pushState,
  // which adds an entry after the one the browser stands on.
  for (final jumps in [true, false]) {
    testWidgets('${after(jumps)}, pushPathState on Login adds its entry', (
      tester,
    ) async {
      final app = await _onLoginAfter(tester, jumps: jumps);

      expect(
        await app.after(
          () => app.router.navigationHistory.pushPathState('picked'),
        ),
        (
          'Login /login [Home Login] [] / /${jumps ? 'a' : 'login'} '
              '>/login#picked',
          jumps ? 'go -2, push /login' : 'push /login',
        ),
      );
      expect(await app.back(), (
        'Login /login [Home Login] [] / >/login /login#picked',
        jumps ? 'replace /login' : '',
      ));
    });
  }

  // Steps: on Home, push B, Item and A, press back three times and sign out.
  // Jump three entries forward, or press forward three times: Login shows in
  // place of A, the entry landed on. The sign-in flow calls popAndPush.
  // Was, after the jump: the jump held the writes until A showed, so Register
  // showed with the browser on the entry of A.
  // Should: as after the forward presses, the step back and the push of
  // /register drop the entry of A.
  // Native behavior this holds to: the HTML standard's history.pushState,
  // which drops the entries ahead.
  for (final jumps in [true, false]) {
    testWidgets('${jumps ? 'After a jump' : 'After forward presses'}, '
        'popAndPush on the sign-in page of the entry landed on writes the '
        'browser', (tester) async {
      final app = await _onHomeAfter(tester, _openBItemThenA);
      app.signingIn = Completer<void>();
      await app.walk(
        jumps ? () => app.browser.didJump(3) : app.browser.didPressForward,
        jumps ? 1 : 3,
      );
      expect(app.shown, startsWith('Login /${jumps ? 'a' : 'login'} '));

      expect(
        await app.after(
          () => unawaited(
            app.router.popAndPush(const NamedRoute<Object?>('Register')),
          ),
        ),
        (
          'Register /register [Home B Item Register] [] / /b /item >/register',
          'go -1, push /register',
        ),
      );
    });
  }

  // Steps: on Home, push A and B, press back and forward. Call popUntilRoot.
  // While its step back is on its way, the platform hands over a link to the
  // page Item, as url_launcher's Link does after popUntilRoot in one tap.
  // Was: the app took the link for a jump over the entry of A and opened A
  // again under Item: the browser held /, /a and /item, and back showed A.
  // Should: Item over Home, and back shows Home with the entry of Item ahead.
  // Native behavior this holds to: Flutter's Navigator, where a popped page
  // stays closed, and the HTML standard's session history, where pushState
  // after the step back drops the entries ahead.
  testWidgets("A link while the app's own step back is on its way is no "
      'jump', (tester) async {
    final app = _App(tester);
    await _openB(app, prefix: false);
    for (final press in [
      app.browser.didPressBack,
      app.browser.didPressForward,
    ]) {
      expect(press(), isTrue);
      await app.browser.settle(tester);
    }
    app.router.popUntilRoot();
    await tester.pump();
    expect(app.browser.isStepping, isTrue);

    expect(await app.after(() => unawaited(app.handOverLink('/item'))), (
      'Item /item [Home Item] [] / >/item',
      'push /item',
    ));
    expect(await app.back(), ('Home / [Home] [] >/ /item', ''));
  });
}
