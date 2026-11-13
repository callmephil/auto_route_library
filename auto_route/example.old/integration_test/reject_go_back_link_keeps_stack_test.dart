import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// A link with a query that a guard turns down with reject(goBack: true)
// leaves the stack as it was, as a refused navigation changes nothing.
// Headless test: auto_route/test/guards/reject_go_back_link_keeps_stack_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('reject goBack link keeps stack', () {
    // Steps: open Home, push<int> Other and wait for its result, then the
    // platform hands the running app the link /secret?x=1, whose guard calls
    // reject(goBack: true). Tap 'Answer 7' on Other.
    // Was: Flutter's duplicate page key assertion in debug builds, and Other
    // twice on the stack in release builds, so closing it showed it again.
    // Should: Other shows once, its caller gets 7, and Home shows after it.
    testWidgets(
      'A link with a query its guard rejects with goBack keeps the stack',
      (tester) async {
        final router = RootStackRouter.build(
          routes: [
            NamedRouteDef(
              name: 'HomeRoute',
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('HomeRoute'))),
            ),
            NamedRouteDef(
              name: 'OtherRoute',
              path: '/other',
              builder: (context, _) => Scaffold(
                body: SafeArea(
                  child: TextButton(
                    onPressed: () => unawaited(context.router.maybePop(7)),
                    child: const Text('Answer 7'),
                  ),
                ),
              ),
            ),
            NamedRouteDef(
              name: 'SecretRoute',
              path: '/secret',
              guards: [
                AutoRouteGuard.simple(
                  (resolver, _) => resolver.reject(goBack: true),
                ),
              ],
              builder: (_, _) =>
                  const Scaffold(body: SafeArea(child: Text('SecretRoute'))),
            ),
          ],
        );
        await pumpRouterConfigApp(
          tester,
          router.config(includePrefixMatches: true),
        );
        var result = 'waiting';
        unawaited(
          router
              .push<int>(const NamedRoute('OtherRoute'))
              .then((value) => result = 'got ${value ?? 'null'}'),
        );
        await tester.pumpAndSettle();

        const codec = JSONMethodCodec();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.navigation.name,
          codec.encodeMethodCall(
            const MethodCall('pushRouteInformation', {
              'location': '/secret?x=1',
              'state': null,
            }),
          ),
          null,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(router.stack.map((page) => page.name), [
          'HomeRoute',
          'OtherRoute',
        ]);
        expect(find.text('Answer 7'), findsOneWidget);
        expect(find.text('SecretRoute'), findsNothing);
        expect(result, 'waiting');

        await tester.tap(find.text('Answer 7'));
        await tester.pumpAndSettle();

        expect(router.stack.map((page) => page.name), ['HomeRoute']);
        expect(find.text('HomeRoute'), findsOneWidget);
        expect(result, 'got 7');
      },
      // On the web the browser opens the app at its url, and goBack goes back
      // in the browser's own history; the link comes this way only off it.
      skip: kIsWeb,
    );
  });
}
