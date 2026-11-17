import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app.dart';
import 'support/pages.dart';

// On Flutter 3.50.0 the web address bar showed every url encoded twice, such
// as '/dessert/100%2525%2520cr%25C3%25A8me', so a refresh opened the wrong
// page. The browser shows a pushed or typed path percent-encoded once, per the
// WHATWG URL standard's path percent-encode set.
// Headless test: auto_route/test/web/url_encoded_once_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('url encoded once', () {
    RootStackRouter buildRouter() => .build(
      routes: [
        AutoRoute(page: FirstRoute.page, path: '/'),
        AutoRoute(page: _DessertRoute.page, path: '/dessert/:name'),
      ],
    );

    // Steps: push a page whose path param is '100% crème', then open the app
    // again at the url it shows, as a refresh does.
    // Should: the url, and on web the address bar, is
    // '/dessert/100%25%20cr%C3%A8me', and the reopened page reads
    // '100% crème' whole.
    testWidgets('A url with a letter outside ASCII is encoded once', (
      tester,
    ) async {
      final router = buildRouter();
      await pumpRouterAppWithConfig(tester, router);
      unawaited(router.push(_DessertRoute(name: '100% crème')));
      await tester.pumpAndSettle();
      final earlier = find.text('100% crème').evaluate().length;
      const encoded = '/dessert/100%25%20cr%C3%A8me';
      expect(router.urlState.uri.toString(), encoded);
      await expectBrowserUrl(encoded);

      await tester.pumpWidget(const SizedBox());
      await pumpRouterApp(tester, buildRouter(), initialLink: encoded);
      expect((earlier, find.text('100% crème').evaluate().length), (1, 1));
      await expectBrowserUrl(encoded);
    });
  });
}

class _DessertRoute extends PageRouteInfo<void> {
  new({required String name}) : super(pageName, rawPathParams: {'name': name});

  static const String pageName = 'DessertRoute';
  static PageInfo page = PageInfo(
    pageName,
    builder: (data) => Text(data.params.getString('name')),
  );
}
