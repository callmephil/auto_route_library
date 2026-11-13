import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';

// Of two links handed to the running app, the one handed over last ends on
// screen, also when deepLinkBuilder answers the earlier one later.
// Headless test: auto_route/test/slow_link_builder_order_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  RootStackRouter buildRouter() => .build(
    routes: [
      for (final (name, path) in [
        ('HomeRoute', '/'),
        ('InfoRoute', '/info'),
        ('OtherRoute', '/other'),
      ])
        NamedRouteDef(
          name: name,
          path: path,
          builder: (_, _) => Scaffold(
            body: SafeArea(child: Center(child: Text(name))),
          ),
        ),
    ],
  );

  group('slow link builder order', () {
    // Steps: deepLinkBuilder waits on /other until the test lets it answer.
    // The platform hands the running app /other, then /info; then the
    // builder answers for /other.
    // Was: Info opened, then Other landed on top of it.
    // Should: Info, the link handed over last, stays on screen.
    testWidgets(
      'Of two links to a running app, the one handed over last ends on screen',
      (tester) async {
        final router = buildRouter();
        final answerOther = Completer<void>();
        await pumpRouterConfigApp(
          tester,
          router.config(
            includePrefixMatches: false,
            deepLinkBuilder: (link) async {
              if (link.path == '/other') await answerOther.future;
              return link;
            },
          ),
        );

        await openLink(tester, '/other');
        await openLink(tester, '/info');
        expect(find.text('InfoRoute'), findsOneWidget);

        answerOther.complete();
        await tester.pumpAndSettle();

        expectCurrentPage(router, 'InfoRoute');
        expect(find.text('OtherRoute'), findsNothing);
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );

    // Steps: deepLinkBuilder waits on every link until the test lets it
    // answer that link. The platform hands the running app /other, then
    // /info; the builder answers /other, then /info.
    // Was: Other opened and /info was dropped, as if a link handed over
    // after it had opened.
    // Should: Info, the link handed over last, ends on screen.
    testWidgets(
      'Of two links a builder answers in the order they came, the one '
      'handed over last ends on screen',
      (tester) async {
        final router = buildRouter();
        final answers = {
          '/other': Completer<void>(),
          '/info': Completer<void>(),
        };
        await pumpRouterConfigApp(
          tester,
          router.config(
            includePrefixMatches: false,
            deepLinkBuilder: (link) async {
              await answers[link.path]?.future;
              return link;
            },
          ),
        );

        await openLink(tester, '/other');
        await openLink(tester, '/info');
        answers['/other']!.complete();
        await tester.pumpAndSettle();
        answers['/info']!.complete();
        await tester.pumpAndSettle();

        expectCurrentPage(router, 'InfoRoute');
        expect(router.currentUrl, '/info');
      },
      // On the web the browser opens the app at its url; a link reaches the
      // running app this way only off it.
      skip: kIsWeb,
    );
  });
}
