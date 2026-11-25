import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// When the tabs of a page that a link or a replace put on are built late and
// turn its route down, the pages that the link or the replace took off come
// back under a page that the app pushed meanwhile
// (callmephil/auto_route_library#58).
// Steps: on Home, push A. Open /depot/hidden: type it into the address bar
// on the web, or off the web get it from the platform, both with
// rebuildStackOnDeepLink, or call replacePath, replace or replaceAll. Or
// replacePath /lazy/attic. Depot loads a library before it builds its tabs,
// a FutureBuilder builds the tabs of Lazy, and neither lists that route.
// While the page waits, push C, then let the tabs build. Press back twice.
// Was: Home and A came back over C, or A over C, and A showed.
// Should: Home, A and C, with C on screen; back shows A, then Home.
// The app's calls run off the web only: on the web, their browser writes
// end on the entry and url of before, so this test can not see them end.
// Headless tests hold them on the web.
// Native behavior this holds to: Flutter's Navigator.replace keeps the routes
// above the route it replaces, and Navigator.removeRoute keeps the order of
// the others. Headless tests:
// auto_route/test/put_back_under_page_pushed_meanwhile_test.dart and
// auto_route/test/web/put_back_under_page_pushed_meanwhile_web_test.dart.

NamedRouteDef _page(String name, String path) =>
    .new(name: name, path: path, builder: (_, _) => Text(name));

RootStackRouter _router(Future<void> gate) => .build(
  routes: [
    _page('Home', '/'),
    _page('A', '/a'),
    _page('C', '/c'),
    NamedRouteDef(
      name: 'Depot',
      path: '/depot',
      builder: (_, _) => DeferredWidget(
        () => gate,
        () => const AutoTabsRouter(
          routes: [NamedRoute<Object?>('Shop'), NamedRoute<Object?>('Desk')],
        ),
        placeholder: const Text('Loading'),
      ),
      children: [
        _page('Shop', 'shop'),
        _page('Desk', 'desk'),
        _page('Hidden', 'hidden'),
      ],
    ),
    NamedRouteDef(
      name: 'Lazy',
      path: '/lazy',
      builder: (_, _) => FutureBuilder<void>(
        future: gate,
        builder: (_, snapshot) => snapshot.connectionState == .done
            ? const AutoTabsRouter(
                routes: [
                  NamedRoute<Object?>('Front'),
                  NamedRoute<Object?>('Rear'),
                ],
              )
            : const Text('Loading'),
      ),
      children: [
        _page('Front', 'front'),
        _page('Rear', 'rear'),
        _page('Attic', 'attic'),
      ],
    ),
  ],
);

const _kDepotHidden = NamedRoute<Object?>(
  'Depot',
  children: [NamedRoute<Object?>('Hidden')],
);

enum _Opening { typedUrl, platformLink, replacePath, replace, replaceAll }

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pages put back under a page pushed meanwhile', () {
    for (final (opening, url) in [
      (_Opening.typedUrl, '/depot/hidden'),
      (_Opening.platformLink, '/depot/hidden'),
      (_Opening.replacePath, '/depot/hidden'),
      (_Opening.replace, '/depot/hidden'),
      (_Opening.replaceAll, '/depot/hidden'),
      (_Opening.replacePath, '/lazy/attic'),
    ]) {
      final isLink = opening == .typedUrl || opening == .platformLink;
      testWidgets(
        '${opening.name} $url: C stays on top, and back shows A, then Home',
        (tester) async {
          final gate = Completer<void>();
          final router = _router(gate.future);
          await pumpRouterConfigApp(
            tester,
            router.config(
              rebuildStackOnDeepLink: isLink,
              includePrefixMatches: false,
              // Opens at '/', whatever url the test before left.
              deepLinkBuilder: (link) =>
                  link.initial ? DeepLink.defaultPath : link,
            ),
          );
          final home = browserEntryIndex();
          unawaited(router.push(const NamedRoute<Object?>('A')));
          await tester.pumpAndSettle();
          final failures = <NavigationFailure>[];
          switch (opening) {
            case .typedUrl:
              typeBrowserUrl(url);
            case .platformLink:
              unawaited(tester.binding.handlePushRoute(url));
            case .replacePath:
              unawaited(router.replacePath(url, onFailure: failures.add));
            case .replace:
              unawaited(router.replace(_kDepotHidden, onFailure: failures.add));
            case .replaceAll:
              unawaited(
                router.replaceAll([_kDepotHidden], onFailure: failures.add),
              );
          }
          await pumpUntilFound(tester, find.text('Loading'));
          unawaited(router.push(const NamedRoute<Object?>('C')));
          await tester.pumpAndSettle();
          // On the web, C's entry is written after the typed entry.
          if (home != null) await expectBrowserEntry(home + 3);
          gate.complete();
          await tester.pumpAndSettle();

          expect(router.stack.map((page) => page.name), ['Home', 'A', 'C']);
          expect(find.text('C'), findsOneWidget);
          if (home != null) await expectBrowserEntry(home + 2);
          await expectBrowserUrl('/c');
          if (kIsWeb) {
            await expectBrowserBackWalk(tester, router, [
              ('A', '/a'),
              ('Home', '/'),
            ]);
            return;
          }
          for (final name in ['A', 'Home']) {
            await systemBack(tester);
            expect(router.topRoute.name, name, reason: 'after a back');
          }
        },
        skip: opening == .typedUrl ? !kIsWeb : kIsWeb,
      );
    }
  });
}
