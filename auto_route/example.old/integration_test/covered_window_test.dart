import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// On macOS the tests keep drawing frames while another window covers the
// app's window, as the iOS simulator's or the Android emulator's can while
// their tests run beside it.
// The engine then reports the app hidden, and a hidden app draws no frames:
// a test waited for nothing and checked the screen in the middle of a move.
// Found as a test of a drag between tabs that failed on macOS only in a run
// beside the other platforms: the view still settled, so it took no taps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('covered window', () {
    // Steps: the tabs TabA and TabB in a page view. Drag TabA a short way
    // toward TabB, then let go as the engine reports the window covered.
    // Was: the view stayed between the tabs and TabA took no taps.
    // Should: the view settles back on TabA.
    testWidgets(
      'A swipe settles while the window is covered',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) => const Scaffold(
                body: AutoTabsRouter.pageView(
                  routes: [
                    NamedRoute<Object?>('TabA'),
                    NamedRoute<Object?>('TabB'),
                  ],
                ),
              ),
              children: [
                for (final name in const ['TabA', 'TabB'])
                  NamedRouteDef(
                    name: name,
                    path: name.substring(3).toLowerCase(),
                    builder: (_, _) => Center(child: Text(name)),
                  ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await pumpRouterApp(tester, router);

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('TabA')),
        );
        await gesture.moveBy(const Offset(-80, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(-80, 0));
        await tester.pump();
        await gesture.up();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.lifecycle.name,
          // As the engine names the state.
          SystemChannels.lifecycle.codec.encodeMessage(
            'AppLifecycleState.hidden',
          ),
          null,
        );
        await tester.pumpAndSettle();

        expect(find.text('TabA').hitTestable(), findsOneWidget);
      },
      // A covered window reports the app hidden on macOS only.
      skip: kIsWeb || defaultTargetPlatform != .macOS,
    );
  });
}
