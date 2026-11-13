import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'router_test_utils.dart';

// DeferredWidget never showed the `placeholder` it was given: it showed the
// router's placeholder, or a progress indicator. Found by the audit of
// auto_route/lib at dev 56b73492 (finding W15).
// Cause: build never read widget.placeholder; upstream commit 88a13f84 (2023)
// replaced `_loadedChild ?? widget.placeholder` with the router's placeholder
// and left the parameter behind.
// Steps: push a page that is a DeferredWidget with its own placeholder, while
// its library loads.
// Should: the placeholder shows until the library has loaded, as the
// parameter's doc comment says: "The widget is displayed until
// [libraryLoader] is done loading". Without one, the router's placeholder
// still shows.
void main() {
  testWidgets('A DeferredWidget shows its own placeholder while its library '
      'loads', (tester) async {
    final library = Completer<void>();
    Future<void> loadLibrary() => library.future;
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
          builder: (_, _) => DeferredWidget(
            loadLibrary,
            () => const Text('DeferredRoute'),
            placeholder: const Text('Loading the page'),
          ),
        ),
      ],
    );
    await pumpRouterApp(tester, router);
    unawaited(router.pushPath('/deferred'));
    // Not pumpAndSettle: the default placeholder spins until the library
    // loads.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final isOwnPlaceholderShown = find
        .text('Loading the page')
        .evaluate()
        .isNotEmpty;

    library.complete();
    await tester.pumpAndSettle();
    expect(find.text('DeferredRoute'), findsOneWidget);
    expect(isOwnPlaceholderShown, isTrue);
  });
}
