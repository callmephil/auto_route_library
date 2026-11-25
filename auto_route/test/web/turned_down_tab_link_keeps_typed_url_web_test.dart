@TestOn('browser')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' show window;

import '../router_test_utils.dart';
import 'browser_history.dart';

// On the web, a typed url that the tabs of a new tabs page turn down keeps
// the url of its entry (callmephil/auto_route_library#60), in a real browser.
// Steps: on Home, push A, type /store/hidden, a child of Store that the tabs
// of Store do not list, then press the browser's forward button. With
// rebuildStackOnDeepLink off and on.
// Was: the app wrote /store/shop over the typed entry, so forward opened
// Store on Shop. With rebuildStackOnDeepLink, the app dropped the typed entry.
// Should: A shows on its entry after each step, as after a root guard's no.
// A back onto Depot, a deferred tabs page that still loads with /depot/hidden,
// puts no page on, so nothing takes Depot back: its url names its first tab.
// Native behavior this holds to: in the HTML standard's session history, a
// traversal changes no entry.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

void main() {
  useRealBrowserHistory();
  setUp(rewindBrowserHistory);

  for (final rebuildStackOnDeepLink in [false, true]) {
    testWidgets('A typed url the tabs turn down keeps its url, and forward '
        'onto it shows A again, rebuildStackOnDeepLink '
        '$rebuildStackOnDeepLink', (tester) async {
      final router = RootStackRouter.build(
        routes: [
          _page('Home', '/'),
          _page('A', '/a'),
          NamedRouteDef(
            name: 'Store',
            path: '/store',
            builder: (_, _) => const AutoTabsRouter(
              routes: [
                NamedRoute<Object?>('Shop'),
                NamedRoute<Object?>('Account'),
              ],
            ),
            children: [
              _page('Shop', 'shop'),
              _page('Account', 'account'),
              _page('Hidden', 'hidden'),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(
        tester,
        router.config(rebuildStackOnDeepLink: rebuildStackOnDeepLink),
      );
      await settleBrowser(tester);
      final home = browserSerialCount;
      unawaited(router.push(const NamedRoute<Object?>('A')));
      await settleBrowser(tester);
      final length = browserEntryCount;
      // The page on top, the pages of the stack, the url and the entry.
      String shown() =>
          '${router.topRoute.name} '
          '[${router.stack.map((page) => page.name).join(' ')}] '
          '$browserPath ${browserSerialCount - home}';

      await browserMove(tester, () => window.location.hash = '/store/hidden');
      final afterLink = shown();
      // The typed entry is still ahead, so the forward button has a step.
      expect(browserEntryCount - length, 1);
      await pressBrowserForward(tester);

      expect((afterLink, shown()), ('A [Home A] /a 1', 'A [Home A] /a 1'));
    });
  }

  for (final isTyped in [false, true]) {
    testWidgets('Back onto a loading tabs page whose tabs turn its url down '
        'names the first tab, and forward changes no entry, typed '
        '$isTyped', (tester) async {
      final depotLibrary = Completer<void>();
      final router = RootStackRouter.build(
        routes: [
          _page('Home', '/'),
          _page('A', '/a'),
          _page('C', '/c'),
          NamedRouteDef(
            name: 'Depot',
            path: '/depot',
            builder: (_, _) => DeferredWidget(
              () => depotLibrary.future,
              () => const AutoTabsRouter(
                routes: [
                  NamedRoute<Object?>('DShop'),
                  NamedRoute<Object?>('DAccount'),
                ],
              ),
              placeholder: const Text('Loading'),
            ),
            children: [
              _page('DShop', 'shop'),
              _page('DAccount', 'account'),
              _page('DHidden', 'hidden'),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final home = browserSerialCount;
      unawaited(router.push(const NamedRoute<Object?>('A')));
      await settleBrowser(tester);
      // The page on top, the pages of the stack, the url and the entry.
      String shown() =>
          '${router.topRoute.name} '
          '[${router.stack.map((page) => page.name).join(' ')}] '
          '$browserPath ${browserSerialCount - home}';

      if (isTyped) {
        await browserMove(tester, () => window.location.hash = '/depot/hidden');
      } else {
        unawaited(router.navigatePath('/depot/hidden'));
        await settleBrowser(tester);
      }
      unawaited(router.push(const NamedRoute<Object?>('C')));
      await settleBrowser(tester);
      await pressBrowserBack(tester);
      depotLibrary.complete();
      await settleBrowser(tester);
      final loaded = shown();
      final length = browserEntryCount;
      await pressBrowserForward(tester);
      final forward = (shown(), browserEntryCount - length);
      await pressBrowserBack(tester);

      expect(
        (loaded, forward, shown()),
        (
          'DShop [Home A Depot] /depot/shop 2',
          ('C [Home A Depot C] /c 3', 0),
          'DShop [Home A Depot] /depot/shop 2',
        ),
      );
    });
  }
}
