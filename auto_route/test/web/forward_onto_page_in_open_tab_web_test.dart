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

// In a real browser, the forward button onto the entry of a page in the tab
// on screen changes no entry (callmephil/auto_route_library#54). The steps,
// what was seen and what should be seen are those of the headless test on
// the VM: test/forward_onto_page_in_open_tab_test.dart.
//
// A url typed into a tab whose router is AutoRouter.declarative, which its
// app does not take, leaves the page shown, and the url names it again.
//
// Native behavior this holds to: the HTML standard's session history, where
// a forward traversal goes to the next entry and adds or changes none.
// Flutter's Router reports the delegate's configuration after
// setNewRoutePath.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router() => .build(
  routes: [
    _page('Home', '/'),
    _page('A', '/a'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Orders')],
        ),
      ),
      children: [
        _page('Shop', 'shop'),
        NamedRouteDef(
          name: 'Orders',
          path: 'orders',
          builder: (_, _) => const AutoRouter(),
          children: [_page('OrdersIndex', ''), _page('Order', ':id')],
        ),
      ],
    ),
  ],
);

// Whether the browser has an entry ahead, as the Navigation API tells.
// Home, and Store on Orders, an AutoRouter.declarative whose app shows the
// pages [listed] names, an id for an Item.
RootStackRouter _declarativeRouter(ValueNotifier<List<String>> listed) =>
    .build(
      routes: [
        _page('Home', '/'),
        NamedRouteDef(
          name: 'Store',
          path: '/store',
          builder: (_, _) => const Scaffold(
            body: AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('Shop'),
                NamedRoute<Object?>('Orders'),
              ],
            ),
          ),
          children: [
            _page('Shop', 'shop'),
            NamedRouteDef(
              name: 'Orders',
              path: 'orders',
              builder: (_, _) => ValueListenableBuilder<List<String>>(
                valueListenable: listed,
                builder: (_, pages, _) => AutoRouter.declarative(
                  routes: (_) => [
                    for (final page in pages)
                      if (page == 'Index')
                        const NamedRoute<Object?>('Index')
                      else
                        NamedRoute<Object?>('Item', params: {'id': page}),
                  ],
                ),
              ),
              children: [_page('Index', ''), _page('Item', ':id')],
            ),
          ],
        ),
      ],
    );

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

// What [backs] presses of the back button and then [forwards] presses of
// the forward button show, until the browser has no entry ahead.
Future<List<String>> _walk(
  WidgetTester tester,
  RootStackRouter router,
  int home, {
  required int backs,
  required int forwards,
}) async {
  final walk = <String>[];
  for (var i = 0; i < backs; i++) {
    await pressBrowserBack(tester);
    walk.add(_shown(router, home));
  }
  for (var i = 0; i < forwards && _canGoForward; i++) {
    await pressBrowserForward(tester);
    walk.add(_shown(router, home));
  }
  return walk;
}

// Opens Order [id] in the Orders tab of [router].
Future<void> _openOrder(
  WidgetTester tester,
  RootStackRouter router,
  String id,
) async {
  final tabs = router.innerRouterOf<TabsRouter>('Store')!;
  unawaited(tabs.innerRouterOf<StackRouter>('Orders')!.pushPath<Object?>(id));
  await settleBrowser(tester);
}

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  testWidgets('After a reload on Order 8 with A ahead, forward walks to A '
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
    await _openOrder(tester, first, '7');
    await _openOrder(tester, first, '8');
    unawaited(first.push(const NamedRoute<Object?>('A')));
    await settleBrowser(tester);
    await pressBrowserBack(tester);
    await tester.pumpWidget(const SizedBox());
    await settleBrowser(tester);
    first.dispose();
    addTearDown(router.dispose);
    openBrowserAt(tester, '/store/orders/8');
    await pumpAsRunApp(
      tester,
      MaterialApp.router(
        routerConfig: router.config(includePrefixMatches: false),
      ),
    );
    final length = browserEntryCount;

    expect(await _walk(tester, router, home, backs: 3, forwards: 4), [
      'Order [Store] /store/orders/7 2',
      'OrdersIndex [Store] /store/orders 1',
      'Home [Home] / 0',
      'OrdersIndex [Home Store] /store/orders 1',
      'Order [Home Store] /store/orders/7 2',
      'Order [Home Store] /store/orders/8 3',
      'A [Home Store A] /a 4',
    ]);
    expect(browserEntryCount, length);
  });

  testWidgets('After a typed url to Order 8 in the tab on screen and a push '
      'of A, forward walks back to A and changes no entry', (tester) async {
    final router = _router();
    await pumpRouterConfigApp(
      tester,
      router.config(rebuildStackOnDeepLink: true, includePrefixMatches: false),
    );
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    await _openOrder(tester, router, '7');
    await browserMove(tester, () => window.location.hash = '/store/orders/8');
    unawaited(router.push(const NamedRoute<Object?>('A')));
    await settleBrowser(tester);
    final length = browserEntryCount;

    expect(await _walk(tester, router, home, backs: 4, forwards: 4), [
      'Order [Store] /store/orders/8 3',
      'Order [Store] /store/orders/7 2',
      'OrdersIndex [Store] /store/orders 1',
      'Home [Home] / 0',
      'OrdersIndex [Home Store] /store/orders 1',
      'Order [Home Store] /store/orders/7 2',
      'Order [Home Store] /store/orders/8 3',
      'A [Home Store A] /a 4',
    ]);
    expect(browserEntryCount, length);
  });

  testWidgets('A typed url that the declarative router of the tab on screen '
      'does not take steps back to the entry of the page shown', (
    tester,
  ) async {
    final listed = ValueNotifier<List<String>>(['Index']);
    addTearDown(listed.dispose);
    final router = _declarativeRouter(listed);
    await pumpRouterConfigApp(tester, router.config());
    await settleBrowser(tester);
    final home = browserSerialCount;
    unawaited(router.pushPath<Object?>('/store/orders'));
    await settleBrowser(tester);
    listed.value = ['Index', '7'];
    await settleBrowser(tester);
    final length = browserEntryCount;

    await browserMove(tester, () => window.location.hash = '/store/orders/8');

    final top = router.topRoute;
    expect(
      (
        '${top.name} ${top.params.optString('id') ?? '-'} '
            '${router.currentUrl} $browserPath ${browserSerialCount - home}',
        browserEntryCount - length,
      ),
      ('Item 7 /store/orders/7 /store/orders/7 2', 1),
    );
  });
}
