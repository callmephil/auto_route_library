import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A deferred page whose library failed to load loads when it is opened again.
// Headless test: auto_route/test/deferred_page_failed_load_retry_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('deferred page failed load retry', () {
    // Steps: tap 'Open deferred' while the page's library fails to load, as
    // on the web when the network drops; go back; tap 'Open deferred' again
    // once the library can load.
    // Was: the loading placeholder showed forever on every later visit.
    // Should: the second visit loads the library and shows the page, as
    // Dart's loadLibrary() starts the load anew after a failure.
    testWidgets('the page loads on the second visit', (tester) async {
      final isOnline = ValueNotifier(false);
      addTearDown(isOnline.dispose);
      Future<void> loadLibrary() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (!isOnline.value) throw StateError('The network dropped');
      }

      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (context, _) => Scaffold(
              body: SafeArea(
                child: TextButton(
                  onPressed: () => context.router.pushPath('/deferred'),
                  child: const Text('Open deferred'),
                ),
              ),
            ),
          ),
          NamedRouteDef(
            name: 'DeferredRoute',
            path: '/deferred',
            builder: (_, _) => DeferredWidget(
              loadLibrary,
              () => const Scaffold(body: Text('Deferred page')),
            ),
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      Future<void> openDeferredPage() async {
        await tester.tap(find.text('Open deferred'));
        // Not pumpAndSettle: the loading placeholder spins until the library
        // loads.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await openDeferredPage();
      final shownOffline = find.text('Deferred page').evaluate().length;
      // Reported as Flutter reports an image that fails to load.
      expect(tester.takeException(), isStateError);

      await systemBack(tester);
      expect(find.text('Open deferred'), findsOneWidget);

      isOnline.value = true;
      await openDeferredPage();
      expect(
        (shownOffline, find.text('Deferred page').evaluate().length),
        (
          0,
          1,
        ),
      );
    });
  });
}
