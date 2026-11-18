import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// callmephil/auto_route_library#11: two links into a page whose nested
// guard is slow, both refused, leave the user where they were.
// Steps: with includePrefixMatches: false, push A over Home. The platform
// hands the app the link '/mail/77' twice while the guard of message 77
// waits. The guard says no to the second ask, then to the first.
// Was: Home, A and Mail on its inbox, at '/mail'.
// Should: Home and A, at '/a', and A's push still waits.
// Native behavior this holds to: on the web a canceled navigation leaves
// the document and its url on screen (HTML standard).
// Headless test: auto_route/test/guards/two_refused_links_into_new_page_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget page(String name) => Scaffold(
    body: SafeArea(child: Center(child: Text(name))),
  );

  // Hands [location] to the running app the way the engine does when the
  // platform opens a link.
  Future<void> openLink(WidgetTester tester, String location) async {
    const codec = JSONMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': location,
          'state': null,
        }),
      ),
      null,
    );
    await tester.pumpAndSettle();
  }

  group('two refused links into new page', () {
    testWidgets('Two refused links keep Home and A', (tester) async {
      final answers = <Completer<bool>>[];
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: 'HomeRoute',
            path: '/',
            builder: (_, _) => page('Home'),
          ),
          NamedRouteDef(
            name: 'ARoute',
            path: '/a',
            builder: (_, _) => page('A'),
          ),
          NamedRouteDef.shell(
            name: 'MailRoute',
            path: '/mail',
            children: [
              NamedRouteDef(
                name: 'InboxRoute',
                path: '',
                builder: (_, _) => page('Inbox'),
              ),
              NamedRouteDef(
                name: 'MessageRoute',
                path: ':id',
                guards: [
                  AutoRouteGuard.simple((resolver, _) async {
                    final answer = Completer<bool>();
                    answers.add(answer);
                    await answer.future ? resolver.next() : resolver.reject();
                  }),
                ],
                builder: (_, _) => page('Message'),
              ),
            ],
          ),
        ],
      );
      await pumpRouterConfigApp(
        tester,
        router.config(includePrefixMatches: false),
      );
      var isAClosed = false;
      unawaited(
        router.push(const NamedRoute('ARoute')).then((_) => isAClosed = true),
      );
      await tester.pumpAndSettle();

      await openLink(tester, '/mail/77');
      await openLink(tester, '/mail/77');
      expect(answers, hasLength(2));
      final [first, second] = answers;
      second.complete(false);
      await tester.pumpAndSettle();
      first.complete(false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.stack.map((page) => page.name), ['HomeRoute', 'ARoute']);
      expect(find.text('A'), findsOneWidget);
      expect(router.currentUrl, '/a');
      expect(isAClosed, isFalse);
      await expectBrowserUrl('/a');
    });
  });
}
