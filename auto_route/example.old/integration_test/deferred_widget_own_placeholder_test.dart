import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A DeferredWidget shows the placeholder it is given while its library
// loads.
// Headless test: auto_route/test/deferred_widget_own_placeholder_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('deferred widget own placeholder', () {
    // Steps: tap 'Open deferred', whose page is a DeferredWidget with the
    // placeholder 'Loading the page', while its library loads; then let the
    // library load.
    // Was: a progress indicator showed instead of the placeholder.
    // Should: 'Loading the page' shows until the page does, as the
    // parameter's doc comment says.
    testWidgets('the page shows its own placeholder while it loads', (
      tester,
    ) async {
      final library = Completer<void>();
      Future<void> loadLibrary() => library.future;
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
              placeholder: const Material(child: Text('Loading the page')),
            ),
          ),
        ],
      );
      await pumpRouterApp(tester, router);

      await tester.tap(find.text('Open deferred'));
      // Not pumpAndSettle: a progress indicator would spin until the library
      // loads.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final shownWhileLoading = find.text('Loading the page').evaluate().length;

      library.complete();
      await tester.pumpAndSettle();
      expect(find.text('Deferred page'), findsOneWidget);
      expect(
        (shownWhileLoading, find.text('Loading the page').evaluate().length),
        (1, 0),
      );
    });
  });
}
