@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../main_router.dart';
import '../router_test_utils.dart';
import '../simple_router/router.dart';
import 'browser_history.dart';

void main() {
  useRealBrowserHistory();

  late SimpleRouter router;
  setUp(() async {
    router = SimpleRouter();
    await rewindBrowserHistory();
  });

  // https://github.com/Milad-Akarie/auto_route_library/issues/2015
  // Start on FirstRoute (the home page), push SecondRoute, push ThirdRoute,
  // then pushAndPopUntil(FirstRoute, predicate: (_) => false).
  // Like Navigator.pushAndRemoveUntil, the call leaves only the home page in
  // the stack. The back button then must not bring a removed page back: the
  // browser stands on the app's first entry again, with no entry of a
  // removed page under it, so its back button leaves the app, as the system
  // back does on the only page. The test can't press it there, since that
  // would leave the test's page.
  testWidgets(
    'The browser back button after pushAndPopUntil on web does not bring a '
    'removed page back',
    (tester) async {
      await pumpRouterConfigApp(tester, router.config());
      await settleBrowser(tester);
      final start = browserSerialCount;

      unawaited(router.push(const SecondRoute()));
      await settleBrowser(tester);
      unawaited(router.push(const ThirdRoute()));
      await settleBrowser(tester);

      unawaited(
        router.pushAndPopUntil(const FirstRoute(), predicate: (_) => false),
      );
      await settleBrowser(tester);
      expect(router.stack.map((p) => p.name), [FirstRoute.name]);
      expectCurrentPage(router, FirstRoute.name);
      expect((browserSerialCount, browserPath), (start, '/'));
    },
  );
}
