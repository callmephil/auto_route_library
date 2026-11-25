import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/browser_walk.dart';

// On the web, with rebuildStackOnDeepLink, back after a typed url shows the
// page of each entry the link closed alone (callmephil/auto_route_library#43).
// Steps: on Home, push A, type /b into the address bar, then press back
// twice and forward twice.
// Was: back showed A over B and wrote /a over the entry of Home, and a
// second back found no entry.
// Should: back shows A alone, then Home alone, one entry each, and forward
// walks the same entries up to B.
// Native behavior this holds to: the HTML standard's session history, where
// a traversal goes to another entry and adds or changes none. Headless tests:
// auto_route/test/rebuild_stack_typed_url_back_test.dart and
// auto_route/test/web/rebuild_stack_typed_url_back_web_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back after a typed url with rebuildStackOnDeepLink', () {
    testWidgets(
      'Back shows A alone, then Home alone',
      (tester) async {
        final router = buildWalkRouter();
        await pumpRouterConfigApp(
          tester,
          router.config(
            rebuildStackOnDeepLink: true,
            // Opens at '/', whatever url the test before left.
            deepLinkBuilder: (link) =>
                link.initial ? DeepLink.defaultPath : link,
          ),
        );
        final home = browserEntryIndex()!;
        unawaited(router.push(const NamedRoute<Object?>('ARoute')));
        await tester.pumpAndSettle();
        typeBrowserUrl('/b');
        await expectBrowserEntry(home + 2);
        await tester.pumpAndSettle();
        expect(router.stack.map((page) => page.name), ['BRoute']);

        for (final (step, url, stack) in [
          (-1, '/a', ['ARoute']),
          (-1, '/', ['HomeRoute']),
          (1, '/a', ['HomeRoute', 'ARoute']),
          (1, '/b', ['HomeRoute', 'ARoute', 'BRoute']),
        ]) {
          await expectBrowserEntryAfter(
            step,
            step < 0 ? pressBrowserBack : pressBrowserForward,
          );
          await tester.pumpAndSettle();
          await expectBrowserUrl(url);
          expect(
            router.stack.map((page) => page.name),
            stack,
            reason: 'the pages at $url',
          );
        }
      },
      skip: !kIsWeb,
    );
  });
}
