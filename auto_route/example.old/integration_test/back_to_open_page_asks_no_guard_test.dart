import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app.dart';
import 'support/pages.dart';

// Issue callmephil/auto_route_library#16: router.back() to a page that is
// still open asked the guard of that page again. The system back button asks
// no guard.
// Native behavior: Flutter's Navigator.pop gives the route under the popped
// one only didPopNext; Android's back and iOS's popViewController ask no
// check of the page that shows again.
// Headless test: auto_route/test/back_to_open_page_asks_no_guard_test.dart.
//
// Off the web only: on the web, back() walks the browser's history.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('back to an open page', () {
    // Steps: push Message (its guard counts its calls), push Settings, call
    // back(); push Settings again and press the system back button.
    // Should: both steps show Message and the guard count stays 1.
    Future<void> asksNoGuard(WidgetTester tester) async {
      final calls = ValueNotifier(0);
      addTearDown(calls.dispose);
      final guard = AutoRouteGuard.simple((resolver, _) {
        calls.value++;
        resolver.next();
      });
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(name: 'HomeRoute', path: '/', builder: _page('Home')),
          NamedRouteDef(
            name: 'MessageRoute',
            path: '/message',
            guards: [guard],
            builder: _page('Message'),
          ),
          NamedRouteDef(
            name: 'SettingsRoute',
            path: '/settings',
            builder: _page('Settings'),
          ),
        ],
      );
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(const NamedRoute('MessageRoute')));
      await tester.pumpAndSettle();
      expect(calls.value, 1);
      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();

      router.back();
      await tester.pumpAndSettle();
      final afterBack = (find.text('Message').evaluate().length, calls.value);

      unawaited(router.push(const NamedRoute('SettingsRoute')));
      await tester.pumpAndSettle();
      await systemBack(tester);
      await tester.pumpAndSettle();
      final afterSystemBack = (
        find.text('Message').evaluate().length,
        calls.value,
      );
      expect((afterBack, afterSystemBack), ((1, 1), (1, 1)));
    }

    testWidgets(
      'back() and system back ask no guard',
      asksNoGuard,
      skip: kIsWeb,
    );
  });
}

Widget Function(BuildContext, RouteData<Object?>) _page(String text) =>
    (_, _) => TextPage(text);
