import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On the web, a typed url that the tabs of a new tabs page turn down keeps
// the url of its entry (callmephil/auto_route_library#60).
// Steps: on Home, push A, type /store/hidden, a child of Store that the tabs
// of Store do not list, then press forward. With rebuildStackOnDeepLink off
// and on.
// Was: the app wrote /store/shop over the typed entry, so forward opened
// Store on Shop; with rebuildStackOnDeepLink, it dropped the typed entry.
// Should: A shows at /a on its entry after each step, as after a guard's no.
// Native behavior this holds to: in the HTML standard's session history, a
// traversal changes no entry. Headless tests:
// auto_route/test/turned_down_tab_link_keeps_typed_url_test.dart and
// auto_route/test/web/turned_down_tab_link_keeps_typed_url_web_test.dart.
// Web only: off the web there is no address bar.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final rebuildStackOnDeepLink in [false, true]) {
    testWidgets(
      'A typed url the tabs turn down keeps its url, and forward shows A '
      'again, rebuildStackOnDeepLink $rebuildStackOnDeepLink',
      (tester) async {
        final router = _storeRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: rebuildStackOnDeepLink,
            // Opens at '/', whatever url the test before left.
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;
        unawaited(router.push(const NamedRoute<Object?>('A')));
        await tester.pumpAndSettle();
        await expectBrowserEntry(home + 1);

        final stacks = <String>[];
        for (final step in [
          () => typeBrowserUrl('/store/hidden'),
          pressBrowserForward,
        ]) {
          // The tabs page opens, then goes back off.
          await _afterPagesChange(tester, router, step);
          await expectBrowserEntry(home + 1);
          await expectBrowserUrl('/a');
          stacks.add(router.stack.map((page) => page.name).join(' '));
        }
        expect(stacks, ['Home A', 'Home A']);
      },
      skip: !kIsWeb,
    );
  }
}

// Runs [step] and waits until the pages of [router] change, then settles.
Future<void> _afterPagesChange(
  WidgetTester tester,
  RootStackRouter router,
  VoidCallback step,
) async {
  final changed = Completer<void>();
  void onChange() {
    if (!changed.isCompleted) changed.complete();
  }

  router.addListener(onChange);
  try {
    step();
    await changed.future.timeout(const Duration(seconds: 5));
  } finally {
    router.removeListener(onChange);
  }
  await tester.pumpAndSettle();
}

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

// Home, A, and Store with the tabs Shop and Account; Store also has the
// child Hidden, which the tabs do not list.
RootStackRouter _storeRouter() => .build(
  routes: [
    _page('Home', '/'),
    _page('A', '/a'),
    NamedRouteDef(
      name: 'Store',
      path: '/store',
      builder: (_, _) => const Scaffold(
        body: AutoTabsRouter(
          routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Account')],
        ),
      ),
      children: [
        _page('Shop', 'shop'),
        _page('Account', 'account'),
        _page('Hidden', 'hidden'),
      ],
    ),
  ],
);
