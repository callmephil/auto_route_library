import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// A deferred page whose library failed to load once never loaded again in
// that run of the app: opening the page again showed the loading placeholder
// forever. Found by the audit of auto_route/lib at dev 56b73492 (finding W4).
// Cause: DeferredWidget._preload kept the future of every loader in a static
// map and never took a failed one out, so the next DeferredWidget with the
// same loader waited on the failed future and the loader wasn't called again.
// Steps: push a deferred page while its library fails to load, as on the web
// when the network drops; pop it; push it again once the library can load.
// Should: the second push calls the loader again and shows the page. Dart's
// deferred loading allows it: `loadLibrary()` can be called again after a
// failure and starts the load anew (dart2js's deferred-load runtime clears
// the failed part, js_helper.dart, so the next call retries), and the Flutter
// docs' deferred components example awaits `loadLibrary()` per widget.
// The failure was an unhandled async error; it is now reported through
// FlutterError.reportError, as Flutter reports an image that fails to load.
void main() {
  testWidgets('A deferred page whose library failed to load loads when '
      'opened again', (tester) async {
    var loadCalls = 0;
    final isOnline = ValueNotifier(false);
    addTearDown(isOnline.dispose);
    Future<void> loadLibrary() async {
      loadCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!isOnline.value) {
        throw StateError('Loading the deferred library failed');
      }
    }

    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: 'HomeRoute',
          path: '/',
          builder: (_, _) => const Text('HomeRoute'),
        ),
        NamedRouteDef(
          name: 'DeferredRoute',
          path: '/deferred',
          builder: (_, _) =>
              DeferredWidget(loadLibrary, () => const Text('DeferredRoute')),
        ),
      ],
    );
    await pumpRouterApp(tester, router);

    Future<void> showDeferredPage() async {
      unawaited(router.pushPath('/deferred'));
      // Not pumpAndSettle: the loading placeholder spins until the library
      // loads.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await showDeferredPage();
    expect(loadCalls, 1);
    expect(find.text('DeferredRoute'), findsNothing);
    // The failed load is reported as Flutter reports an image that fails to
    // load.
    expect(tester.takeException(), isStateError);

    router.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('HomeRoute'), findsOneWidget);

    isOnline.value = true;
    await showDeferredPage();
    expect(loadCalls, 2, reason: 'the second visit loads the library again');
    expect(find.text('DeferredRoute'), findsOneWidget);
  });
}
