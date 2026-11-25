@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// In a real browser, after a link replaces the stack, the app's next push
// adds one entry, and forward presses change no entry
// (callmephil/auto_route_library#51, and the first cause of
// callmephil/auto_route_library#54). The steps, what was seen and what
// should be seen are those of the headless test on the VM:
// test/rebuild_stack_push_after_link_test.dart.
//
// Native behavior this holds to: the HTML standard's session history, where
// history.pushState adds one entry after the current one and a back or
// forward traversal adds or changes none.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router() => .build(
  routes: [
    _page('Home', '/'),
    _page('A', '/a'),
    _page('B', '/b'),
    _page('C', '/c'),
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
        _page('Orders', 'orders'),
        _page('Account', 'account'),
      ],
    ),
  ],
);

// Whether the browser has an entry ahead, as the Navigation API tells.
bool get _canGoForward => globalContext
    .getProperty<JSObject>('navigation'.toJS)
    .getProperty<JSBoolean>('canGoForward'.toJS)
    .toDart;

// The page on top, the pages of the stack, the browser's url and its entry,
// counted from [home].
String _shown(RootStackRouter router, int home) =>
    '${router.topRoute.name} '
    '[${router.stack.map((page) => page.name).join(' ')}] '
    '$browserPath ${browserSerialCount - home}';

// What each press shows, back for true and forward for false, until the
// browser has no entry ahead.
Future<List<String>> _walk(
  WidgetTester tester,
  RootStackRouter router,
  int home,
  List<bool> presses,
) async {
  final walk = <String>[];
  for (final isBack in presses) {
    if (!isBack && !_canGoForward) break;
    await (isBack ? pressBrowserBack(tester) : pressBrowserForward(tester));
    walk.add(_shown(router, home));
  }
  return walk;
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('A push after a typed url adds one entry after its entry', (
    tester,
  ) async {
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true, includePrefixMatches: true),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.push(const NamedRoute<Object?>('A')));
    await settleBrowser(tester);
    await browserMove(tester, () => window.location.hash = '/b');
    unawaited(router.push(const NamedRoute<Object?>('C')));
    await settleBrowser(tester);
    final afterPush = _shown(router, home);

    await pressBrowserBack(tester);

    expect(
      (afterPush, _shown(router, home)),
      ('C [Home B C] /c 3', 'B [Home B] /b 2'),
    );
  });

  testWidgets('After a typed url to Account and a push of A, forward walks '
      'back to A and changes no entry', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true, includePrefixMatches: false),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    await browserMove(tester, () => window.location.hash = '/store/account');
    unawaited(router.push(const NamedRoute<Object?>('A')));
    await settleBrowser(tester);
    final length = browserEntryCount;

    final walk = await _walk(tester, router, home, [
      true,
      true,
      true,
      false,
      false,
      false,
    ]);

    expect(walk, [
      'Account [Store] /store/account 2',
      'Orders [Store] /store/orders 1',
      'Home [Home] / 0',
      'Orders [Home Store] /store/orders 1',
      'Account [Home Store] /store/account 2',
      'A [Home Store A] /a 3',
    ]);
    expect(browserEntryCount, length);
  });

  testWidgets('After a reload on Account with A ahead, forward walks to A '
      'and changes no entry', (tester) async {
    // The app before the reload, and the app after it.
    final [first, router] = [for (var i = 0; i < 2; i++) _router()];
    await pumpRouterConfigApp(
      tester,
      first.config(includePrefixMatches: false),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(first.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    first.innerRouterOf<TabsRouter>('Store')!.setActiveIndex(2);
    await settleBrowser(tester);
    unawaited(first.push(const NamedRoute<Object?>('A')));
    await settleBrowser(tester);
    await pressBrowserBack(tester);
    await tester.pumpWidget(const SizedBox());
    await settleBrowser(tester);
    first.dispose();
    addTearDown(router.dispose);
    openBrowserAt(tester, '/store/account');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(
        routerConfig: router.config(includePrefixMatches: false),
      ),
    );
    final length = browserEntryCount;

    final walk = await _walk(tester, router, home, [
      true,
      true,
      false,
      false,
      false,
    ]);

    expect(walk, [
      'Orders [Store] /store/orders 1',
      'Home [Home] / 0',
      'Orders [Home Store] /store/orders 1',
      'Account [Home Store] /store/account 2',
      'A [Home Store A] /a 3',
    ]);
    expect(browserEntryCount, length);
  });
}
