// Runs only in Chrome, `flutter test --platform chrome`: it needs the web
// engine's answer.
@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_history.dart';

// Canary for state restoration on the web: Flutter's web engine does not
// answer the restoration channel, so the restoration manager turns
// restoration off and hands out no bucket.
// On the web AutoRouterDelegate.currentConfiguration is null, so that the
// Router writes nothing to the browser. The Router reads that value for one
// more thing, the route it saves for state restoration, and saves nothing
// there on the web only because restoration is off.
// Setup: the engine takes platform messages, which it ignores in a widget
// test by default, and a RestorationManager of Flutter's own; the test
// binding swaps in one that always has a bucket. Either default would prove
// nothing.
// Steps: ask the engine for the restoration data, and the manager for its
// root bucket; the navigation channel, which the engine does answer, shows
// that the question reached it.
// If this test fails after a Flutter upgrade, the web engine now restores
// state: the Router then saves a null route on the web. Rework
// AutoRouterDelegate.currentConfiguration and this canary together.
void main() {
  useRealBrowserHistory();

  testWidgets('the web engine does not answer the restoration channel, so a '
      'restoration manager hands out no bucket', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final answered = await messenger.send(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('selectMultiEntryHistory'),
      ),
    );
    expect(answered, isNotNull);
    final reply = await messenger.send(
      'flutter/restoration',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('get')),
    );
    expect(reply, isNull);

    final manager = RestorationManager();
    addTearDown(manager.dispose);
    final bucket = await manager.rootBucket.timeout(const Duration(seconds: 2));
    expect(bucket, isNull);
  });
}
